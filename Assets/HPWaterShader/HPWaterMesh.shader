Shader "HanPiWater/WaterMesh"
{
    Properties
    {
        [HDR] _ScatterColor("Scatter Color", Color) = (0.004, 0.012, 0.020, 1.0)
        [HDR] _AbsorptionColor("Absorption Color", Color) = (0.02, 0.08, 0.15, 1.0)

        _NormalMap("NormalMap", 2D) = "bump" {}
        _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.1

        [HDR] _FoamColor("Foam Color", Color) = (1.0, 1.0, 1.0, 1.0)
        _FoamIntensity("Foam Intensity", Range(0.0, 1.0)) = 0.0

        [Enum(None, 0, Phong, 1)] _TessellationMode("Tessellation mode", Float) = 0
        _TessellationFactor("Tessellation Factor", Range(0.0, 64.0)) = 64
        _TessellationFactorMinDistance("Tessellation start fading distance", Float) = 0
        _TessellationFactorMaxDistance("Tessellation end fading distance", Float) = 0
        _TessellationFactorTriangleSize("Tessellation triangle size", Float) = 0
        _TessellationShapeFactor("Tessellation shape factor", Range(0.0, 1.0)) = 0.75
        _TessellationBackFaceCullEpsilon("Tessellation back face epsilon", Range(-1.0, 0.0)) = -1
        [HiddenInInspector] _TessellationObjectScale("Tessellation object scale", Float) = 1.0
        [HiddenInInspector] _TessellationTilingScale("Tessellation tiling scale", Float) = 1.00
        _TessellationMaxDisplacement("Tessellation Displacement", Float) = 1.0
    }

    HLSLINCLUDE
    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/ShaderVariables.hlsl"
    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/ShaderPass/FragInputs.hlsl"
    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/ShaderPass/ShaderPass.cs.hlsl"
    ENDHLSL

    // ========================================================================
    SubShader
    {
        Tags { "RenderPipeline" = "HDRenderPipeline" }

        // ────────────────────────────────────────────────────────────────────
        // Pass 1: Main GBuffer  (HPWaterGBuffer)
        // Writes:  RT0 = normalWS (octahedral) + roughness
        //          RT1 = scatterColor
        //          RT2 = absorptionColor.rgb + foam.a
        //          Depth via SV_Position
        // ────────────────────────────────────────────────────────────────────
        Pass
        {
            Name "HPWaterGBuffer"
            Tags { "LightMode" = "HPWaterGBuffer" }

            Cull Back
            ZWrite On
            ZTest LEqual

            // Stencil: water surface flag (matches C# in HPWaterGbuffer.cs)
            Stencil
            {
                WriteMask [_StencilWaterWriteMaskGBuffer]
                Ref [_StencilWaterRefGBuffer]
                Comp Always
                Pass Replace
            }

            HLSLPROGRAM
            #pragma target 4.5

            #define SHADERPASS SHADERPASS_GBUFFER
            #define ATTRIBUTES_NEED_NORMAL
            #define ATTRIBUTES_NEED_TANGENT
            #define ATTRIBUTES_NEED_TEXCOORD0
            #define ATTRIBUTES_NEED_TEXCOORD1
            #define ATTRIBUTES_NEED_TEXCOORD2
            #define ATTRIBUTES_NEED_TEXCOORD3
            #define ATTRIBUTES_NEED_COLOR

            #define VARYINGS_NEED_POSITION_WS
            #define VARYINGS_NEED_TANGENT_TO_WORLD
            #define VARYINGS_NEED_TEXCOORD0
            #define VARYINGS_NEED_TEXCOORD1
            #define VARYINGS_NEED_TEXCOORD2
            #define VARYINGS_NEED_TEXCOORD3
            #define VARYINGS_NEED_COLOR
            #define VARYINGS_NEED_CULLFACE

            #define DEBUGMODE_ON
            #define TESSELLATION_ON
            
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GeometricTools.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Tessellation.hlsl"
            #include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/Material.hlsl"
            #include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/ShaderPass/VaryingMesh.hlsl"
            #include "Packages/com.unity.render-pipelines.high-definition/Runtime/HanPiWater/Deferred/HPWater.hlsl"
            #include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/MaterialUtilities.hlsl"

            float _Smoothness;
            float4 _FoamColor;
            float4 _ScatterColor;
            float4 _AbsorptionColor;
#ifdef TESSELLATION_ON
            float _TessellationFactor;
            float _TessellationFactorMinDistance;
            float _TessellationFactorMaxDistance;
            float _TessellationFactorTriangleSize;
            float _TessellationShapeFactor;
            float _TessellationBackFaceCullEpsilon;
            float _TessellationObjectScale;
            float _TessellationTilingScale;
            float _TessellationMaxDisplacement;
#endif

            float GetTessellationFactor(AttributesMesh input)
            {
                return _TessellationFactor;
            }

            float GetMaxDisplacement()
            {
                return _TessellationMaxDisplacement;
            }

            void GetSurfaceAndBuiltinData(FragInputs fragInputs, float3 viewDirection, inout PositionInputs posInput, out SurfaceData surfaceData, out BuiltinData builtinData)
            {
                ZERO_BUILTIN_INITIALIZE(builtinData);

                GetNormalWS_SrcWS(fragInputs, fragInputs.tangentToWorld[2], surfaceData.normalWS, 0);
                surfaceData.normalWS = SafeNormalize(surfaceData.normalWS);
                surfaceData.geomNormalWS = surfaceData.normalWS;
                surfaceData.perceptualSmoothness = _Smoothness;
                surfaceData.foam = _FoamColor;
                surfaceData.scatterColor = _ScatterColor;
                surfaceData.absorptionColor = _AbsorptionColor;

            }

            #include "Packages/com.unity.render-pipelines.high-definition/Runtime/HanPiWater/Gbuffer/HPWaterPassGbuffer.hlsl"

            #pragma vertex Vert
            #pragma fragment Frag
            #pragma hull Hull
            #pragma domain Domain

            ENDHLSL
        }

        // ────────────────────────────────────────────────────────────────────
        // Pass 2: HPWaterCausticGBufferPass
        // Writes:  RT0 = normalWS (octahedral) + roughness
        //          RT1 = scatterColor
        //          RT2 = absorptionColor.rgb + foam.a
        //          Depth via SV_Position
        // ────────────────────────────────────────────────────────────────────
        Pass
        {
            Name "HPWaterGBuffer"
            Tags { "LightMode" = "HPWaterCausticGBufferPass" }

            Cull Back
            ZWrite On
            ZTest LEqual

            // // Stencil: water surface flag (matches C# in HPWaterGbuffer.cs)
            // Stencil
            // {
            //     WriteMask [_StencilWaterWriteMaskGBuffer]
            //     Ref [_StencilWaterRefGBuffer]
            //     Comp Always
            //     Pass Replace
            // }

            HLSLPROGRAM
            #pragma target 4.5

            #define SHADERPASS SHADERPASS_GBUFFER
            #define ATTRIBUTES_NEED_NORMAL
            #define ATTRIBUTES_NEED_TANGENT
            #define ATTRIBUTES_NEED_TEXCOORD0
            #define ATTRIBUTES_NEED_TEXCOORD1
            #define ATTRIBUTES_NEED_TEXCOORD2
            #define ATTRIBUTES_NEED_TEXCOORD3
            #define ATTRIBUTES_NEED_COLOR

            #define VARYINGS_NEED_POSITION_WS
            #define VARYINGS_NEED_TANGENT_TO_WORLD
            #define VARYINGS_NEED_TEXCOORD0
            #define VARYINGS_NEED_TEXCOORD1
            #define VARYINGS_NEED_TEXCOORD2
            #define VARYINGS_NEED_TEXCOORD3
            #define VARYINGS_NEED_COLOR
            #define VARYINGS_NEED_CULLFACE

            #define WRITE_NORMAL_BUFFER
            #define TESSELLATION_ON
            
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GeometricTools.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Tessellation.hlsl"
            #include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/Material.hlsl"
            #include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/ShaderPass/VaryingMesh.hlsl"
            #include "Packages/com.unity.render-pipelines.high-definition/Runtime/HanPiWater/Deferred/HPWater.hlsl"
            #include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/MaterialUtilities.hlsl"

            float _Smoothness;
            float4 _FoamColor;
            float4 _ScatterColor;
            float4 _AbsorptionColor;
#ifdef TESSELLATION_ON
            float _TessellationFactor;
            float _TessellationFactorMinDistance;
            float _TessellationFactorMaxDistance;
            float _TessellationFactorTriangleSize;
            float _TessellationShapeFactor;
            float _TessellationBackFaceCullEpsilon;
            float _TessellationObjectScale;
            float _TessellationTilingScale;
            float _TessellationMaxDisplacement;
#endif

            float GetTessellationFactor(AttributesMesh input)
            {
                return _TessellationFactor;
            }

            float GetMaxDisplacement()
            {
                return _TessellationMaxDisplacement;
            }

            void GetSurfaceAndBuiltinData(FragInputs fragInputs, float3 viewDirection, inout PositionInputs posInput, out SurfaceData surfaceData, out BuiltinData builtinData)
            {
                ZERO_BUILTIN_INITIALIZE(builtinData);

                GetNormalWS_SrcWS(fragInputs, fragInputs.tangentToWorld[2], surfaceData.normalWS, 0);
                surfaceData.normalWS = SafeNormalize(surfaceData.normalWS);
                surfaceData.geomNormalWS = surfaceData.normalWS;
                surfaceData.perceptualSmoothness = _Smoothness;
                surfaceData.foam = _FoamColor;
                surfaceData.scatterColor = _ScatterColor;
                surfaceData.absorptionColor = _AbsorptionColor;

            }

            #include "Packages/com.unity.render-pipelines.high-definition/Runtime/HanPiWater/Caustic/HPWaterCausticGbufferPass.hlsl"

            #pragma vertex Vert
            #pragma fragment Frag
            #pragma hull Hull
            #pragma domain Domain

            ENDHLSL
        }

        Pass
        {
            Name "HPWaterFluidHeight"
            Tags { "LightMode" = "HPWaterFluidDynamicsPass" }

            Cull Off
            ZWrite On
            ZTest LEqual
            Blend Off

            HLSLPROGRAM
            #pragma target 4.5

            #include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/Material.hlsl"
            #include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/ShaderPass/VaryingMesh.hlsl"
            #include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/MaterialUtilities.hlsl"
            #include "Packages/com.unity.render-pipelines.high-definition/Runtime/HanPiWater/Deferred/HPWater.hlsl"


            float _Smoothness;
            float4 _FoamColor;
            float4 _ScatterColor;
            float4 _AbsorptionColor;

            void GetSurfaceAndBuiltinData(FragInputs fragInputs, float3 viewDirection, inout PositionInputs posInput, out SurfaceData surfaceData, out BuiltinData builtinData)
            {
                ZERO_BUILTIN_INITIALIZE(builtinData);

                GetNormalWS_SrcWS(fragInputs, fragInputs.tangentToWorld[2], surfaceData.normalWS, 0);
                surfaceData.normalWS = SafeNormalize(surfaceData.normalWS);
                surfaceData.geomNormalWS = surfaceData.normalWS;
                surfaceData.perceptualSmoothness = _Smoothness;
                surfaceData.foam = _FoamColor;
                surfaceData.scatterColor = _ScatterColor;
                surfaceData.absorptionColor = _AbsorptionColor;
            }

            #include "Packages/com.unity.render-pipelines.high-definition/Runtime/HanPiWater/FluidDynamics/ShaderPassHPWaterFluidDynamics.hlsl"

            #pragma vertex Vert
            #pragma fragment Frag

            ENDHLSL
        }
    }
    Fallback Off
}
