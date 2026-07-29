#ifndef WAVE_HEIGHT_SAMPLE_INCLUDED
#define WAVE_HEIGHT_SAMPLE_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/HanPiWater/HPWaterCommon.hlsl"
#define mySampler s_linear_clamp_sampler

TEXTURE2D(_HPWaterWaveHeightTexture);
float3 _HPWaterFluidDynamicsBoxCenter;
float3 _HPWaterFluidDynamicsBoxSize;
int _HPWaterFluidDynamicsEnabled;

// 世界坐标转UV
float2 WorldPosToFluidUV(float3 worldPos)
{
    // 计算相对于Box中心的偏移
    float offsetX = worldPos.x - _HPWaterFluidDynamicsBoxCenter.x;
    float offsetZ = worldPos.z - _HPWaterFluidDynamicsBoxCenter.z;
    
    // 归一化到[0, 1]范围
    float u = (offsetX * rcp(_HPWaterFluidDynamicsBoxSize.x)) + 0.5;
    float v = (offsetZ * rcp(_HPWaterFluidDynamicsBoxSize.z)) + 0.5;
    
    return float2(u, v);
}

bool IsInsideHPWaterFluidDomain(float2 uv)
{
    return _HPWaterFluidDynamicsEnabled != 0 && all(uv >= 0.0) && all(uv <= 1.0);
}

// 使用世界坐标采样波高
void HPWaterFluidHeight_float(float3 worldPos, out float waveHeight)
{
    float2 uv = WorldPosToFluidUV(worldPos);
    waveHeight = IsInsideHPWaterFluidDomain(uv)
        ? SAMPLE_TEXTURE2D_LOD(_HPWaterWaveHeightTexture, mySampler, uv, 0).r
        : 0.0;
}

// 高度转法线
void HPWaterFluidHeightToNormal_float(float3 worldPosition, out float3 OutNormal)
{
    if (_HPWaterFluidDynamicsEnabled == 0)
    {
        OutNormal = float3(0.0, 1.0, 0.0);
        return;
    }

    uint width, height;
    _HPWaterWaveHeightTexture.GetDimensions(width, height);

    float2 uv = WorldPosToFluidUV(worldPosition);
    if (!IsInsideHPWaterFluidDomain(uv) || width == 0 || height == 0)
    {
        OutNormal = float3(0.0, 1.0, 0.0);
        return;
    }
    // 偏移向量
    float2 offsetU = float2(rcp(width), 0.0);
    float2 offsetV = float2(0.0, rcp(height));

    // 采样周围 4 个点的高度 (中心差分)
    float hLeft  = SAMPLE_TEXTURE2D_LOD(_HPWaterWaveHeightTexture, mySampler, uv - offsetU, 0).r;
    float hRight = SAMPLE_TEXTURE2D_LOD(_HPWaterWaveHeightTexture, mySampler, uv + offsetU, 0).r;
    float hDown  = SAMPLE_TEXTURE2D_LOD(_HPWaterWaveHeightTexture, mySampler, uv - offsetV, 0).r;
    float hUp    = SAMPLE_TEXTURE2D_LOD(_HPWaterWaveHeightTexture, mySampler, uv + offsetV, 0).r;

    // 世界尺寸
    float2 worldSize = _HPWaterFluidDynamicsBoxSize.xz * rcp(width);
    // 法线强度 : 1 / Δx
    float2 normalStrength = 1.0 * rcp(worldSize * 2);

    // 计算梯度 (斜率)
    float dX = (hLeft - hRight) * normalStrength.x;
    float dY = (hDown - hUp) * normalStrength.y;

    OutNormal = safeNormalize(float3(dX, 1.0, dY));
}

// 混合世界法线
void HPWaterFluidWorldNormalBlend_float(float3 normalInput1,float3 normalInput2, out float3 OutNormal)
{
    float2 xz = normalInput1.xz + normalInput2.xz;
    float y = normalInput1.y * normalInput2.y;
    OutNormal = safeNormalize(float3(xz.x, y, xz.y));
}

// Shared by the camera GBuffer and the caustic GBuffer so both observe the
// same simulated surface. positionRWS is camera-relative in HDRP, while the
// fluid domain supplied by C# is absolute world space.
void ApplyHPWaterFluidDisplacement(inout AttributesMesh inputMesh)
{
    if (_HPWaterFluidDynamicsEnabled == 0)
        return;

    float3 positionRWS = TransformObjectToWorld(inputMesh.positionOS);
    float3 absolutePositionWS = GetAbsolutePositionWS(positionRWS);
    float2 fluidUV = WorldPosToFluidUV(absolutePositionWS);
    if (!IsInsideHPWaterFluidDomain(fluidUV))
        return;

    float waveHeight;
    HPWaterFluidHeight_float(absolutePositionWS, waveHeight);
    positionRWS.y += waveHeight;
    inputMesh.positionOS = TransformWorldToObject(positionRWS);

#if defined(ATTRIBUTES_NEED_NORMAL)
    float3 fluidNormalWS;
    HPWaterFluidHeightToNormal_float(absolutePositionWS, fluidNormalWS);
    float3 baseNormalWS = TransformObjectToWorldNormal(inputMesh.normalOS);
    float3 blendedNormalWS;
    HPWaterFluidWorldNormalBlend_float(baseNormalWS, fluidNormalWS, blendedNormalWS);
    inputMesh.normalOS = TransformWorldToObjectDir(blendedNormalWS);
#endif
}

#ifdef TESSELLATION_ON
void ApplyHPWaterFluidDisplacementToDS(inout VaryingsMeshToDS inputMesh)
{
    if (_HPWaterFluidDynamicsEnabled == 0)
        return;

    float3 absolutePositionWS = GetAbsolutePositionWS(inputMesh.positionRWS);
    float2 fluidUV = WorldPosToFluidUV(absolutePositionWS);
    if (!IsInsideHPWaterFluidDomain(fluidUV))
        return;

    float waveHeight;
    HPWaterFluidHeight_float(absolutePositionWS, waveHeight);
    inputMesh.positionRWS.y += waveHeight;

#if defined(ATTRIBUTES_NEED_NORMAL)
    float3 fluidNormalWS;
    HPWaterFluidHeightToNormal_float(absolutePositionWS, fluidNormalWS);
    float3 blendedNormalWS;
    HPWaterFluidWorldNormalBlend_float(inputMesh.normalWS, fluidNormalWS, blendedNormalWS);
    inputMesh.normalWS = blendedNormalWS;
#endif
    
}
#endif


#endif
