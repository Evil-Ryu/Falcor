
#pragma once
#include "Falcor.h"

using namespace Falcor;


class ShaderEditor : public IRenderer
{
public:
    ~ShaderEditor();

    void onLoad(RenderContext* pRenderContext) override;
    void onFrameRender(RenderContext* pRenderContext, const Fbo::SharedPtr& pTargetFbo) override;
    void onShutdown() override;
    void onResizeSwapChain(uint32_t width, uint32_t height) override;
    bool onKeyEvent(const KeyboardEvent& keyEvent) override;
    bool onMouseEvent(const MouseEvent& mouseEvent) override;

    void onGuiRender(Gui* pGui);

private:


    Sampler::SharedPtr              mpLinearSampler;
    float                           mAspectRatio = 0;
    RasterizerState::SharedPtr      mpNoCullRastState;
    DepthStencilState::SharedPtr    mpNoDepthDS;
    BlendState::SharedPtr           mpOpaqueBS;

    struct HLFullScreenPass
    {
        FullScreenPass::SharedPtr mPass;
        Fbo::SharedPtr mFbo;
        std::string mShaderPath;
        bool mActive = false;
    };

    std::vector<HLFullScreenPass> mPasses;

    FullScreenPass::SharedPtr mBlitPass;
    FullScreenPass::SharedPtr mClearPass;
    bool mNeedsClear = false;
    bool mCameraDirty = false;

    Texture::SharedPtr mpTex;
    std::string mTexPath;

    std::vector<float> mControllableVars;

    float mTime = 0.f;
    float mFrame = 0.f;

    float mMaxSPP = 1024;



    CameraController::SharedPtr mpCamCtrl;
    std::vector<Camera::SharedPtr> mCameras;
    float mCameraSpeed = 1.f;

    // for debug
    Texture::SharedPtr mDebugTexture;



    void setPass(const int index);
    Texture::SharedPtr loadImage();
    void setCommonVars(FullScreenPass::SharedPtr &pass, float w, float h);
    void executeBlitPass(RenderContext* pRenderContext, Texture::SharedPtr srcTexture, Fbo::SharedPtr dstFbo);
    void executeClearPass(RenderContext* pRenderContext, Fbo::SharedPtr Fbo);
    void resetCamera();
    void createFbos(uint32_t width, uint32_t height);
    void createDebugResources();
};
