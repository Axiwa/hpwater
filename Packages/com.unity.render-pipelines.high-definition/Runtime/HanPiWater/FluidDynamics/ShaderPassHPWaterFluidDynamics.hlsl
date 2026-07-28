float4x4 _HPWaterFluidViewProjMatrix;
float3 _HPWaterVirtualCameraPos;

struct Attributes
{
    float3 positionOS : POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float4 positionCS : SV_Position;
    float3 positionRWS : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

Varyings Vert(Attributes input)
{
    Varyings output;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);

    // HDRP returns camera-relative world space here when that feature is enabled.
    float3 positionRWS = TransformObjectToWorld(input.positionOS);
    float3 positionAWS = GetAbsolutePositionWS(positionRWS);
    output.positionRWS = positionAWS - _HPWaterVirtualCameraPos;
    output.positionCS = mul(_HPWaterFluidViewProjMatrix, float4(output.positionRWS, 1.0));
    return output;
}

float Frag(Varyings input) : SV_Target0
{
    UNITY_SETUP_INSTANCE_ID(input);
    return input.positionRWS.y;
}