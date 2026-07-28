Shader "Hidden/HDRP/HanPiWater/HPWater"
{
    HLSLINCLUDE
        #pragma target 4.5
        #pragma enable_d3d11_debug_symbols
        // #pragma use_dxc         
        // #pragma target 6.0
        #pragma editor_sync_compilation
        #pragma only_renderers d3d11 playstation xboxone xboxseries vulkan metal switch
        #pragma multi_compile _ _USE_RAY_MARCHING_ON
        
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
        #include "Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/ShaderVariables.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
        #include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/NormalBuffer.hlsl"
        #include "Packages/com.unity.render-pipelines.high-definition/Runtime/HanPiWater/Deferred/HPWaterLightLoopData.hlsl"
        #include "Packages/com.unity.render-pipelines.high-definition/Runtime/HanPiWater/HPWaterCommon.hlsl"        
        #include "Packages/com.unity.render-pipelines.high-definition/Runtime/HanPiWater/HPWaterGlobalShaderVariable.cs.hlsl"
        #include "Packages/com.unity.render-pipelines.high-definition/Runtime/HanPiWater/Caustic/HPWaterCausticPass.cs.hlsl"  
        #include "Packages/com.unity.render-pipelines.high-definition/Runtime/HanPiWater/Caustic/HPWaterCaustic.hlsl"
        #include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/HDStencilUsage.cs.hlsl"

        #define DIGITS_OFFSET_L 1e-4

        struct Attributes
        {
            uint vertexID : SV_VertexID;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float2 texcoord   : TEXCOORD0;
            UNITY_VERTEX_OUTPUT_STEREO
        };

        Varyings Vert(Attributes input)
        {
            Varyings output;
            UNITY_SETUP_INSTANCE_ID(input);
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
            output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
            output.texcoord = GetFullScreenTriangleTexCoord(input.vertexID);
            return output;
        }

        // ========================================================
        // Pass 0: CopyDepth
        // ========================================================
        TEXTURE2D (_inputTexture);   

        float CopyDepth(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            
            // 获取纹理尺寸并转换为像素坐标
            uint width, height;
            _inputTexture.GetDimensions(width, height);
            uint2 pixelCoord = uint2(floor(input.texcoord * float2(width, height)));
            
            float depth = _inputTexture.Load(int3(pixelCoord, 0)).r;
            
            return depth;
        }

        // ========================================================
        // Pass 1: PackToFloat - 单通道模式
        // ========================================================        
        Texture2D<uint> _causticIrradianceRT_G_Read;

        float FragSingleChannel(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            
            // 获取纹理尺寸并转换为像素坐标
            uint width, height;
            _causticIrradianceRT_G_Read.GetDimensions(width, height);
            uint2 pixelCoord = min(uint2(input.positionCS.xy), uint2(width - 1, height - 1));
            
            // 从整数纹理读取并转换为浮点
            uint g = _causticIrradianceRT_G_Read.Load(int3(pixelCoord, 0));
            
            return (float)g * DIGITS_OFFSET_L;
        }

        // ========================================================
        // Pass 2: À-trous第2次迭代（使用mipmap，基于深度差）
        // ========================================================
    #define MAX_MIP_LEVEL 6
    #define LUMEN_MIP_MAX 4 //多少级后停止Lumen权重

        // À-trous降噪参数
        float _AtrousLuminanceWeight;
        float _MipRangePerLevel;   
        TEXTURE2D (_causticRT_Color_FLOAT);
        Texture2D<float> _WaterCascadeDepth0Atlas;
        Texture2D<float> _ShadowDepthCascadeAtlas;
        Texture2D<float>  _WaterCascadeDepth1Atlas;
        Texture2D<float2> _WaterGbuffer1Atlas; 

        // À-trous 3x3核
        static const float atrousKernel3x3[3][3] = {
            {1.0/16.0, 2.0/16.0, 1.0/16.0},
            {2.0/16.0, 4.0/16.0, 2.0/16.0},
            {1.0/16.0, 2.0/16.0, 1.0/16.0}
        };
        
        float FragAtrousSingle_ColorToIrradiance(Varyings input) : SV_Target 
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            uint width, depthWidth, gbufferWidth;
            _causticRT_Color_FLOAT.GetDimensions(width, width);
            _ShadowDepthCascadeAtlas.GetDimensions(depthWidth, depthWidth);
            
            float2 uv = input.texcoord;
            // 读取水体深度
            float waterDepth = _WaterCascadeDepth0Atlas.Load(int3(uv * float2(width, width), 0));
            //大概率能Return，最先检查   
            [branch]
            if(waterDepth == 0)return 0;

            // 读取场景深度
            float sceneDepth = _ShadowDepthCascadeAtlas.Load(int3(uv * float2(depthWidth, depthWidth), 0));    
            //中概率能Return，紧接着检查
            [branch]
            if(sceneDepth == 0)return 0;
            
            // 确定当前像素所属的级联
            int cascadeIndex = GetCascadeIndexFromAtlasUV(uv, width);
            
            // 将归一化深度转换为米单位
            float waterDepthMeters = NormalizedDepthToMeters(waterDepth, 0);
            float sceneDepthMeters = NormalizedDepthToMeters(sceneDepth, 0);
            
            // 计算深度差（米）
            float depthDiff = abs(sceneDepthMeters - waterDepthMeters);

            _WaterGbuffer1Atlas.GetDimensions(gbufferWidth, gbufferWidth);
            float2 gbuffer = _WaterGbuffer1Atlas.Load(int3(uv * float2(gbufferWidth, gbufferWidth), 0));
            //Packages\com.unity.render-pipelines.high-definition\Runtime\HanPiWater\Deferred\HPWater.hlsl
            float absorptionValue, scatteringValue;
            DecodeHPWaterCausticGBufferUpsampling(_WaterGbuffer1Atlas, _WaterCascadeDepth1Atlas, s_point_clamp_sampler,
            uv, waterDepth, width, absorptionValue, scatteringValue);

            // 计算模糊等级（HPWaterBSDFLibary.hlsl）
            float r2noise = R2_dither(uv * float2(width, width), 0);
            float mipLevel = CalculateHPWaterMipLevel(depthDiff, CAUSTIC_SCALING_FACTOR, scatteringValue, MAX_MIP_LEVEL);
            //加入噪声，打破mipmap分界线
            mipLevel -= r2noise * 0.25;
            mipLevel = max(mipLevel, 0);

            // 中心点采样
            float centerColor = SAMPLE_TEXTURE2D_LOD(_causticRT_Color_FLOAT, s_linear_clamp_sampler, uv, mipLevel).r;
            float centerLum = centerColor;

            
            float result = 0;
            float weightSum = 0;
            
            // 随 Mip 等级扩大的步长
            // 如果 mipLevel 是 3，意味着纹理缩小了 2^3 = 8 倍
            // 我们的采样步长也要扩大 8 倍，否则还在同一个像素里打转
            float mipScale = exp2(mipLevel); 
            float2 baseStride = rcp(float(width)) * max(mipScale,2);// 最小步长为2 

            // 随机偏移+旋转            
            float c, s;
            sincos(6.2831853 * r2noise * 0.125, s, c);//核为3x3，8个方向
            float2x2 rotMatrix = float2x2(c, -s, s, c);

            float wLuminance = 1.0;

            // À-trous Loop
            [unroll]
            for (int y = -1; y <= 1; y++) 
            {
                [unroll]
                for (int x = -1; x <= 1; x++) 
                {
                    // 使用扩大后的步长
                    float2 offset = float2(x, y) * baseStride; // *2 是 Atrous 固有步长
                    float2 rotatedOffset = mul(rotMatrix, offset);//旋转后的偏移
                    float2 sampleUV = uv + rotatedOffset;
                    
                    float sampleColor = SAMPLE_TEXTURE2D_LOD(_causticRT_Color_FLOAT, s_linear_clamp_sampler, sampleUV, mipLevel).r;
                    float sampleLum = sampleColor;
                    if(mipLevel < LUMEN_MIP_MAX)
                    {
                        wLuminance = ComputeEdgeWeight(centerLum, sampleLum, _AtrousLuminanceWeight);
                        wLuminance = lerp(wLuminance, 1.0, mipLevel * rcp(LUMEN_MIP_MAX));
                    }
                    else
                    {
                        wLuminance = 1.0;
                    }
                    
                    float spatialWeight = atrousKernel3x3[y + 1][x + 1];
                    float w = spatialWeight * wLuminance;
                    
                    result += sampleColor * w;
                    weightSum += w;
                }
            }
            
            return result / max(weightSum, 1e-6);
        }

        // ========================================================
        // Pass 3: Refraction
        // ========================================================
        TEXTURE2D_X(_DepthTexture);             // 主深度（包含水面）
        TEXTURE2D_X_UINT2(_StencilTexture);     // Stencil 纹理（用于判断水面像素）
        TEXTURE2D_X(_HPWaterGBuffer0);          // 水体 GBuffer0 (normalWS + roughness)
        
        int _Ray_Marching_Sample_Count;

        // XY = UV offset, Z = raw depth at the final refracted UV, W = water mask.
        float4 FragRefraction(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            // 直接使用 input.positionCS.xy 作为像素坐标（已经是正确的屏幕空间坐标）
            uint2 positionSS = uint2(input.positionCS.xy);
            
            // 【DX11 修复】手动 Stencil 判断，替代硬件 Stencil 测试（避免读写冲突）
            // 参考 HPWaterVolume.cs 的做法，使用 _StencilTexture 判断水面像素
            uint stencilValue = GetStencilValue(LOAD_TEXTURE2D_X(_StencilTexture, positionSS));
            [branch]
            if ((stencilValue & STENCILUSAGE_USER_BIT0) == 0)
            {
                // 不是水面像素，直接返回零偏移
                return 0;
            }

            // 读取场景深度（从 _CameraDepthTexture，已覆盖绑定为 depthPyramid，不含水面）    
            float sceneDepth = LOAD_TEXTURE2D_X(_CameraDepthTexture, positionSS).r;
            bool directViewHitsSky = IsSky(sceneDepth);

            // 读取水面深度（从 _DepthTexture，包含水面）
            float waterDepth = LOAD_TEXTURE2D_X(_DepthTexture, positionSS).r;

             // 读取水体法线 (从 GBuffer0)
            float4 normalData = LOAD_TEXTURE2D_X(_HPWaterGBuffer0, positionSS);
            NormalData normalDataDecode;
            DecodeFromNormalBuffer(normalData, normalDataDecode);
            float3 normalWS = normalDataDecode.normalWS;
                                    
            // 使用 GetPositionInput 重建世界坐标，直接传入像素坐标
            PositionInputs waterPosInput = GetPositionInput(positionSS, _ScreenSize.zw, waterDepth, 
                                                            UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
            PositionInputs scenePosInput = GetPositionInput(positionSS, _ScreenSize.zw, sceneDepth, 
                                                            UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
            
            float3 waterWorldPos = waterPosInput.positionWS;
            float3 sceneWorldPos = scenePosInput.positionWS;
            
            // 使用 PositionInputs 中的 NDC 坐标
            float2 positionNDC = waterPosInput.positionNDC;
            
            //----------------------------------------------------------
            //准备开始光线步进
            //----------------------------------------------------------
            // 参数初始化            
                
            static const float eta = 1.0 / 1.33; // 空气到水的折射率

            float3 refractedWorldPos;            
            // 注意：在 Camera Relative Rendering 模式下，waterWorldPos 已经是相对坐标（相机在原点）
            float3 camera2WaterDir = -GetWorldSpaceNormalizeViewDir(waterWorldPos);
            // A sky pixel has no finite scene position. Its incident direction is
            // still the camera ray through the water surface.
            float3 waterCrossDir = directViewHitsSky
                ? camera2WaterDir
                : safeNormalize(sceneWorldPos - waterWorldPos);
            
            // 计算折射向量
            float refractionStrength = max(_RefractionStrength, 0.0);
            float3 normalGain = float3(refractionStrength, 1.0, refractionStrength);
            float3 refractDir = refract(camera2WaterDir, safeNormalize(normalWS * normalGain), eta);
            
            // 舍弃整体上的折射，只捕捉法线产生的折射
            float3 refractedDir_Fix = refract(camera2WaterDir, float3(0, 1, 0), eta);
            refractDir -= refractedDir_Fix; // No Snell Refraction!
            refractDir += waterCrossDir;

            // 检查是否发生全反射
            [branch]
            if (length(refractDir) == 0) return 0;
            refractDir = safeNormalize(refractDir);

            // Ray Marching 参数，在这里放弃了Hiz光线步进，因为这里并不需要处理很远的距离，用Hiz反而是负优化
            //这里的随机光线步进是为了查出来折射后的真实大概深度，不然折射后的颜色会停留在当前物体的深度上，因此查找的位置不需要很精确
        #define REFRACT_SAMPLE_COUNT _Ray_Marching_Sample_Count
        #define REFRACT_THICKNESS_OFFSET 0.1 // 厚度阈值，单位：米       

            //NDC空间光线步进
            float3 rayStart = waterWorldPos;
            float3 refractDirection = refractDir;
            float3 startNDC = ComputeNormalizedDeviceCoordinatesWithZ(rayStart, UNITY_MATRIX_VP);
            startNDC.z = LinearEyeDepth(startNDC.z, _ZBufferParams);
            float3 endNDC = ComputeNormalizedDeviceCoordinatesWithZ(waterWorldPos + refractDir * _MaxRefractionCrossDistance, UNITY_MATRIX_VP);
            endNDC.z = LinearEyeDepth(endNDC.z, _ZBufferParams);
            float3 ndcDir = endNDC - startNDC;

            // Keep the fallback finite for sky pixels. The ray march below can
            // still replace it when the refracted ray crosses visible geometry.
            float fallbackDistance = directViewHitsSky
                ? _MaxRefractionCrossDistance
                : min(length(sceneWorldPos - waterWorldPos), _MaxRefractionCrossDistance);
            refractedWorldPos = waterWorldPos + refractDir * max(fallbackDistance, 0.001);
            float3 hitNDC = ComputeNormalizedDeviceCoordinatesWithZ(refractedWorldPos, UNITY_MATRIX_VP);

            //Dither IGN
            float  dither = GenerateRandom1DOffset(positionNDC,_ScreenSize.xy, GetTaaFrameInfo().z);
            static float expFactor = ADAPTIVE_EXP_FACTOR_STATIC(_MaxRefractionCrossDistance,REFRACTION_REFERENCE_DISTANCE);

            // 预计算指数步进
            float rcpCount = rcp(float(REFRACT_SAMPLE_COUNT));
            float kDenom = rcp(expFactor - 1.0);

            // 预计算步进乘数：exp(ln(expFactor) / N) -> expFactor^(1/N)
            float expStep = pow(expFactor, rcpCount);

            // 计算起始点的 exp 值：expFactor^(Dither/N)
            float currentExp = pow(expFactor, dither * rcpCount);

#if defined(_USE_RAY_MARCHING_ON)
            // Ray Marching
            float previousDepthDelta = -1e20;
            [loop]            
            for (int i = 0; i < REFRACT_SAMPLE_COUNT; i++)
            {
                float d = (currentExp - 1.0) * kDenom;
                float3 samplePositionNDC = startNDC + ndcDir * d;

                // 检查是否在有效范围内
                if (any(samplePositionNDC.xy < 0) || any(samplePositionNDC.xy > 1)) break;
                
                float rayMarchLinearDepth = samplePositionNDC.z;
                float2 rayScreenUV = samplePositionNDC.xy;
                int2 rayScreenCoord = int2(rayScreenUV * _ScreenSize.xy);
                int2 rayScreenCoordMip = rayScreenCoord >> 0;
                float raySceneRawDepth = LOAD_TEXTURE2D_X(_CameraDepthTexture, rayScreenCoordMip).r;
                
                // 转换为线性深度（单位：米），用于精确的厚度比较
                float raySceneLinearDepth = LinearEyeDepth(raySceneRawDepth, _ZBufferParams);
                currentExp *= expStep;

                // Sky contributes color but has no depth surface to intersect.
                if (IsSky(raySceneRawDepth))
                {
                    previousDepthDelta = -1e20;
                    continue;
                }

                float depthDelta = rayMarchLinearDepth - raySceneLinearDepth;
                bool withinThickness = abs(depthDelta) <= REFRACT_THICKNESS_OFFSET;
                bool crossedSurface = previousDepthDelta < -REFRACT_THICKNESS_OFFSET
                    && depthDelta > REFRACT_THICKNESS_OFFSET;

                // Detect both a close sample and a front-to-back depth crossing.
                // The crossing test is important when a refracted ray enters an
                // object's silhouette from a sky pixel between two march steps.
                if (withinThickness || crossedSurface)
                {
                    //refractedWorldPos = samplePos;
                    hitNDC = samplePositionNDC;
                    break; // 找到交点，退出循环    
                }

                previousDepthDelta = depthDelta;
            }
#endif
            // 边界因子 (防止边缘穿帮)
            #define REFRACT_BOUND_SCALE_X 6
            #define REFRACT_BOUND_SCALE_Y 6
            
            float safaRefractBound_X = saturate(positionNDC.x * REFRACT_BOUND_SCALE_X) * saturate((1.0 - positionNDC.x) * REFRACT_BOUND_SCALE_X);
            float safaRefractBound_Y = saturate(positionNDC.y * REFRACT_BOUND_SCALE_Y) * saturate((1.0 - positionNDC.y) * REFRACT_BOUND_SCALE_Y);

            // 先计算折射后的屏幕坐标（不含前向散射）
            float2 refractWaterScreenCoord = hitNDC.xy;
            refractWaterScreenCoord = saturate(refractWaterScreenCoord);   
        
            // Read the candidate position only for the above-water rejection.
            int2 refractedCoordSS = clamp(int2(refractWaterScreenCoord.xy * _ScreenSize.xy),
                0, int2(_ScreenSize.xy) - 1);
            float refractedRawDepth = LOAD_TEXTURE2D_X(_CameraDepthTexture, refractedCoordSS).r;
            
            // 使用 GetPositionInput 重建折射后的世界坐标
            PositionInputs refractedPosInput = GetPositionInput(refractedCoordSS, _ScreenSize.zw, refractedRawDepth, 
                                                                UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
            float3 refractedBackWorldPos = refractedPosInput.positionWS;

            // 应用边界因子
            float2 uvOffset = refractWaterScreenCoord - positionNDC;
            uvOffset *= saturate(pow(safaRefractBound_X * safaRefractBound_Y,0.5));
            
            // 判断折射后的世界坐标是否在水中，如果在水面上方则使用原始坐标
            if (!IsSky(refractedRawDepth) && refractedBackWorldPos.y > waterWorldPos.y)
            {
                uvOffset = 0;
            }
            
            // Limit
            uvOffset = clamp(uvOffset, -1, 1);

            // Edge fading and above-water rejection can change the UV after the
            // candidate depth was loaded. Sample depth again at the final UV so
            // refractionData.xy and refractionData.z describe the same pixel.
            float2 finalRefractedUV = saturate(positionNDC + uvOffset);
            int2 finalRefractedCoordSS = clamp(int2(finalRefractedUV * _ScreenSize.xy),
                0, int2(_ScreenSize.xy) - 1);
            float finalRefractedRawDepth = LOAD_TEXTURE2D_X(_CameraDepthTexture, finalRefractedCoordSS).r;
            
            return float4(uvOffset, finalRefractedRawDepth, 1);
        }

        // ========================================================
        // Pass 4: CaculateFluidBoundary
        // ========================================================
        float CaculateFluidBoundary(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            
            // 获取纹理尺寸并转换为像素坐标
            uint width, height;
            _inputTexture.GetDimensions(width, height);
            uint2 pixelCoord = uint2(floor(input.texcoord * float2(width, height)));
            
            float depth = _inputTexture.Load(int3(pixelCoord, 0)).r;
            
            return depth;
        }
    ENDHLSL

    SubShader
    {
        Tags{ "RenderPipeline" = "HDRenderPipeline" }

        // CopyDepth
        Pass
        {
            Name "CopyDepth"
            ZWrite Off ZTest Always Blend Off Cull Off

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment CopyDepth
            ENDHLSL
        }

        // Pass 1: PackToFloat - 单通道模式
        Pass
        {
            Name "PackToFloat"
            ZWrite Off ZTest Off Blend Off Cull Off

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragSingleChannel
            ENDHLSL
        }

        // Pass 2: À-trous Single ColorToIrradiance
        Pass
        {
            Name "AtrousSingle_ColorToIrradiance"
            ZWrite Off ZTest LEqual Blend Off Cull Off

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragAtrousSingle_ColorToIrradiance
            ENDHLSL
        }

        // Pass 3: Refraction
        Pass
        {
            Name "Refraction"
            // 【DX11 修复】移除硬件 Stencil 测试和 ZTest，避免深度缓冲读写冲突
            // 改为在 Fragment Shader 中手动判断 Stencil（通过 _StencilTexture）
            ZWrite Off ZTest Always Blend Off Cull Off

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragRefraction
            ENDHLSL
        }
    }
    Fallback Off
}
