using UnityEngine;
using UnityEngine.Rendering.HighDefinition;

[ExecuteAlways]
public class HPWaterParametersProvider : MonoBehaviour
{
    [Header("Water Body")]
    public float maxCrossDistance = 100.0f;
    public float refractionStrength = 1.0f;
    public float indirectLightStrength = 1.0f;
    public float maxRefractionCrossDistance = 20.0f;
    public float multiScatterScale = 10.0f;
    public float forwardScatterBlurDensity = 0.5f;
    public float phaseG = 0.80f;
    public float causticShadowAlphaClipThreshold = 0.8f;

    [Header("Caustics")]
    public int causticRenderSize = 1024;
    public int gbuffer1AtlasSize = 256;
    public int waterCascadeAtlasSize = 1024;
    public bool useRGBCaustic = false;
    public float causticIntensity = 1.0f;
    public float crossDistance = 1.0f;
    public float dispersionStrength = 0.1f;
    public float causticDispersionStrength = 0.1f;
    public float waterDispersionStrength = 0.1f;
    public float forwardRandomOffset = 1.0f;
    public float atrousLuminanceWeight = 0.5f;
    public bool useAtrousDenoise = false;

    [Header("Refraction")]
    public bool useRayMarching = false;
    public int rayMarchingSampleCount = 8;

    [Header("Deferred Lighting")]
    [Range(0.1f, 1.0f)]
    public float volumeResolutionScale = 0.5f;
    public bool enableSpatialFilter = true;
    public int spatialFilterIterations = 2;
    public bool enableDepthAwareUpsampling = true;
    public float temporalBlendFactor = 0.9f;
    public bool enableMotionVectors = true;
    public float motionVectorVelocityScale = 0.1f;
    public bool enableTemporalDepthRejection = true;
    public float temporalDepthThreshold = 0.5f;
    public bool enableSpatialDepthAware = true;
    public float spatialDepthSensitivity = 100.0f;
    public float shadowSoftness = 1.0f;
    public int blockerSampleCount = 16;
    public int filterSampleCount = 16;
    public float minFilterSize = 0.1f;

    [Header("Fluid Dynamics (Wave Simulation)")]
    public bool enableFluidDynamics = true;
    public bool startFrameBakeProcess = false;
    public Vector3 fluidBoxCenter = new Vector3(0, 0, 0);
    public Vector3 fluidBoxSize = new Vector3(20, 20, 20);
    public float fluidCameraHeight = 15.0f;
    public int sceneDepthTextureResolution = 256;
    public int waterDepthTextureResolution = 256;
    public int waveHeightTextureResolution = 256;
    public float waveSpeed = 2.0f;
    public float dampingFactor = 0.001f;
    public float waveSourceRadius = 1.0f;

    [SerializeField] LayerMask waterInteractionMask;
    [SerializeField] float clickStrength = 4.0f;
    [SerializeField] float clickRadiusPixels = 16.0f;
    private Vector2 m_WaveSourceUV = new Vector2(-1, -1);
    private float m_WaveSourceIntensity;
    private int m_WaveSourceFrame = -1;

    private HDRenderPipeline.WaterRefractionInputData ProvideWaterRefraction()
    {
        return new HDRenderPipeline.WaterRefractionInputData
        {
            useRayMarching = useRayMarching,
            rayMarchingSampleCount = rayMarchingSampleCount
        };
    }

    private HDRenderPipeline.HPWaterVolumeInputData ProvideWaterVolume()
    {
        return new HDRenderPipeline.HPWaterVolumeInputData
        {
            // resolutionScale              = volumeResolutionScale,
            // temporalBlendFactor          = temporalBlendFactor,
            // enableSpatialFilter          = enableSpatialFilter,
            // spatialFilterIterations      = spatialFilterIterations,
            // enableDepthAwareUpsampling   = enableDepthAwareUpsampling,
            // enableMotionVectors          = enableMotionVectors,
            // motionVectorVelocityScale    = motionVectorVelocityScale,
            // enableTemporalDepthRejection = enableTemporalDepthRejection,
            // temporalDepthThreshold       = temporalDepthThreshold,
            // enableSpatialDepthAware      = enableSpatialDepthAware,
            // spatialDepthSensitivity      = spatialDepthSensitivity,
            // shadowSoftness               = shadowSoftness,
            // blockerSampleCount           = blockerSampleCount,
            // filterSampleCount            = filterSampleCount,
            // minFilterSize                = minFilterSize
        };
    }

    private HDRenderPipeline.CausticInputData ProvideCaustic()
    {
        return new HDRenderPipeline.CausticInputData
        {
            // causticRenderSize      = causticRenderSize,
            // gbuffer1AtlasSize      = gbuffer1AtlasSize,
            // waterCascadeAtlasSize  = waterCascadeAtlasSize,
            useRGBCaustic          = false,
            // showDebugInfo          = false,
            // useSpecifiedMaterial   = false,
            // specifiedMaterial      = null,
            // depthBias              = 1.0f,
            // slopeBias              = 0.5f,
            // forwardRandomOffset    = forwardRandomOffset,
            // causticIntensity       = causticIntensity,
            // crossDistance          = crossDistance,
            // dispersionStrength     = dispersionStrength,
            // atrousLuminanceWeight  = atrousLuminanceWeight,
            // useAtrousDenoise       = useAtrousDenoise
        };
    }

    private HDRenderPipeline.HPWaterFluidDynamicsInputData ProvideFluidDynamics()
    {
        bool hasSource = m_WaveSourceFrame == Time.frameCount;
        return new HDRenderPipeline.HPWaterFluidDynamicsInputData
        {
            startFrameBakeProcess         = startFrameBakeProcess,
            boxCenter                     = fluidBoxCenter,
            boxSize                       = fluidBoxSize,
            sceneDepthTextureResolution   = sceneDepthTextureResolution,
            waterDepthTextureResolution   = waterDepthTextureResolution,
            waveHeightTextureResolution   = waveHeightTextureResolution,
            cameraHeight                  = fluidCameraHeight,
            waveSpeed                     = waveSpeed,
            dampingFactor                 = dampingFactor,
            waveSourceRadius              = waveSourceRadius,
            waveSourceUV                  = hasSource ? m_WaveSourceUV : new Vector2(UnityEngine.Random.value * 0.5f, UnityEngine.Random.value * 0.5f),
            waveSourceIntensity           = hasSource ? m_WaveSourceIntensity : 1.0f
        };
    }

    private HDRenderPipeline.HPWaterGlobalParams ProvideGlobalParams()
    {
        return new HDRenderPipeline.HPWaterGlobalParams
        {
            _MaxCrossDistance            = maxCrossDistance,
            _RefractionStrength          = refractionStrength,
            _IndirectLightStrength       = indirectLightStrength,
            _MaxRefractionCrossDistance  = maxRefractionCrossDistance,
            _MultiScatterScale           = multiScatterScale,
            _CausticDispersionStrength   = causticDispersionStrength,
            _WaterDispersionStrength     = waterDispersionStrength,
            _ForwardScatterBlurDensity   = forwardScatterBlurDensity,
            _PhaseG                      = phaseG,
            _CausticShadowAlphaClipThreshold = causticShadowAlphaClipThreshold,
            _Is_Use_RGB_Caustic          = useRGBCaustic ? 1 : 0,
            _UnusedHPWaterGlobalParams   = 0.0f
        };
    }

    private void OnEnable()
    {
        HDRenderPipeline.OnGetWaterRefractionParameters     += ProvideWaterRefraction;
        HDRenderPipeline.OnGetHPWaterVolumeInputData        += ProvideWaterVolume;
        HDRenderPipeline.OnGetCausticParameters             += ProvideCaustic;
        HDRenderPipeline.OnGetHPWaterFluidDynamicsInputData += ProvideFluidDynamics;
        HDRenderPipeline.OnGetHPWaterGlobalParams           += ProvideGlobalParams;
    }

    private void OnDisable()
    {
        HDRenderPipeline.OnGetWaterRefractionParameters     -= ProvideWaterRefraction;
        HDRenderPipeline.OnGetHPWaterVolumeInputData        -= ProvideWaterVolume;
        HDRenderPipeline.OnGetCausticParameters             -= ProvideCaustic;
        HDRenderPipeline.OnGetHPWaterFluidDynamicsInputData -= ProvideFluidDynamics;
        HDRenderPipeline.OnGetHPWaterGlobalParams           -= ProvideGlobalParams;
    }

    private void Update()
    {
        if (Input.GetMouseButton(0))
            TriggerWaveSource(-clickStrength);

        if (Input.GetMouseButton(1))
            TriggerWaveSource(clickStrength / 2);
    }

    private void TriggerWaveSource(float intensity)
    {
        Camera cam = Camera.main;

        if (cam == null)
            return;

        Ray ray = cam.ScreenPointToRay(Input.mousePosition);

        if (!Physics.Raycast(
                ray,
                out RaycastHit hit,
                10000.0f))
        {
            return;
        }

        Vector3 worldPos = hit.point;

        Vector2 uv = new Vector2(
            (worldPos.x - fluidBoxCenter.x) / fluidBoxSize.x + 0.5f,
            (worldPos.z - fluidBoxCenter.z) / fluidBoxSize.z + 0.5f);

        if (uv.x < 0 || uv.x > 1 ||
            uv.y < 0 || uv.y > 1)
        {
            return;
        }

        m_WaveSourceUV = uv;
        m_WaveSourceIntensity = intensity;
        m_WaveSourceFrame = Time.frameCount;
    }
}
