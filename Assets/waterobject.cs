using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.HighDefinition; // 假设你的命名空间

[ExecuteAlways]
public class WaterRefractionManager : MonoBehaviour
{
    // 创建提供参数的方法
    private HDRenderPipeline.WaterRefractionInputData ProvideWaterRefractionParameters()
    {
        HDRenderPipeline.WaterRefractionInputData data = new HDRenderPipeline.WaterRefractionInputData();

        // 根据你的 WaterRefractionInputData 定义填写具体参数
        // 示例参数（你需要根据实际结构填充）：
        data.useRayMarching = true;
        data.rayMarchingSampleCount = 8;

        return data;
    }

    private HDRenderPipeline.HPWaterVolumeInputData ProvideWaterVolumeParameters()
    {
        HDRenderPipeline.HPWaterVolumeInputData data = new HDRenderPipeline.HPWaterVolumeInputData();
        data.enableSpatialFilter = true;

        return data;
    }

    private HDRenderPipeline.CausticInputData ProvideCausticParameters()
    {
        HDRenderPipeline.CausticInputData data = new HDRenderPipeline.CausticInputData();

        return data;
    }

    private void OnEnable()
    {
        // 订阅事件
        HDRenderPipeline.OnGetWaterRefractionParameters += ProvideWaterRefractionParameters;
        HDRenderPipeline.OnGetHPWaterVolumeInputData += ProvideWaterVolumeParameters;
        HDRenderPipeline.OnGetCausticParameters += ProvideCausticParameters;
    }

    private void OnDisable()
    {
        // 取消订阅，避免内存泄漏
        HDRenderPipeline.OnGetWaterRefractionParameters -= ProvideWaterRefractionParameters;
        HDRenderPipeline.OnGetHPWaterVolumeInputData -= ProvideWaterVolumeParameters;
        HDRenderPipeline.OnGetCausticParameters -= ProvideCausticParameters;
    }
}