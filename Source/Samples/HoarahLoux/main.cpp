
#include "main.h"

#define MAX_PASSES 5
#define MAX_CONTROLLABLE_VARS 5
#define DEFAULT_WIDTH 1280
#define DEFAULT_HEIGHT 720

//#define DEFAULT_WIDTH 1024
//#define DEFAULT_HEIGHT 1024


static std::string getFilenameFromPath(const std::string& path)
{
    std::size_t found = path.find_last_of("/\\");
    return path.substr(found + 1);
}

ShaderEditor::~ShaderEditor()
{
}

Texture::SharedPtr ShaderEditor::loadImage()
{
    bool generateMips = true;
    bool loadSRGB = false;

    std::filesystem::path path;
    FileDialogFilterVec filterVec;
    filterVec.push_back(FileDialogFilter("jpg"));
    filterVec.push_back(FileDialogFilter("dds"));
    filterVec.push_back(FileDialogFilter("bmp"));
    filterVec.push_back(FileDialogFilter("png"));

    Texture::SharedPtr pTex = nullptr;

    if (openFileDialog(filterVec, path))
    {
        mTexPath = std::string(path.string());
        pTex = Texture::createFromFile(path, generateMips, loadSRGB);
    }

    return pTex;
}

void ShaderEditor::resetCamera()
{
    auto camera = mCameras[0];
   
    camera->setPosition(float3(-4.76, 4.86, 29.46));
    camera->setTarget(float3(-4.72, 4.87, 28.46));
    // for skybox
    /*camera->setPosition(float3(6.64, 10., -1.79));
    camera->setTarget(float3(6.53, 10.,-2.8));*/
    camera->setUpVector(float3(0, 1, 0));

    {
        float nearZ = 0.1f;
        float farZ = 1000.f;
        camera->setDepthRange(nearZ, farZ);
    }
}

// for capturing skybox
void ShaderEditor::RotateCamera90AroundUp()
{
    auto mpCamera = mCameras[0];

    float3 camPos = mpCamera->getPosition();
    float3 camTarget = mpCamera->getTarget();
    float3 camUp = mpCamera->getUpVector();

    float3 viewDir = glm::normalize(camTarget - camPos);

    float3 sideway = glm::cross(viewDir, normalize(camUp));

    float2 rotation = float2(glm::pi<float>() / 2., glm::pi<float>() / 2.);

    // Rotate around x-axis
    //glm::quat qy = glm::angleAxis(rotation.y, sideway);
    //glm::mat3 rotY(qy);
    //viewDir = viewDir * rotY;
    //camUp = camUp * rotY;

    // Rotate around y-axis
    glm::quat qx = glm::angleAxis(rotation.x, camUp);
    glm::mat3 rotX(qx);
    viewDir = viewDir * rotX;

    mpCamera->setTarget(camPos + viewDir);
    mpCamera->setUpVector(camUp);
}

void ShaderEditor::RotateCamera90AroundRight()
{
    auto mpCamera = mCameras[0];

    float3 camPos = mpCamera->getPosition();
    float3 camTarget = mpCamera->getTarget();
    float3 camUp = mpCamera->getUpVector();

    float3 viewDir = glm::normalize(camTarget - camPos);

    float3 sideway = glm::cross(viewDir, normalize(camUp));

    float2 rotation = float2(glm::pi<float>() / 2., glm::pi<float>() / 2.);

    // Rotate around x-axis
    glm::quat qy = glm::angleAxis(rotation.y, sideway);
    glm::mat3 rotY(qy);
    viewDir = viewDir * rotY;
    camUp = camUp * rotY;

    mpCamera->setTarget(camPos + viewDir);
    mpCamera->setUpVector(camUp);
}

void ShaderEditor::createFbos(uint32_t width, uint32_t height)
{
    // create fbo for each pass
    const ResourceFormat depthFormat = ResourceFormat::D32Float;
    const ResourceFormat colorFormat = ResourceFormat::RGBA32Float;  // pathtracer needs this precision to accumulate color
    Fbo::Desc fboDesc;
    fboDesc.setDepthStencilTarget(depthFormat);
    fboDesc.setColorTarget(0, colorFormat);
    uint32_t mipLevels = Texture::kMaxPossible;

    for (int i = 0; i < MAX_PASSES; ++i)
    {
        mPasses[i].mFbo = Fbo::create2D(width, height, fboDesc, 1, mipLevels);
    }
}

void ShaderEditor::createDebugResources()
{
    mDebugTexture = Texture::create2D(DEFAULT_WIDTH, DEFAULT_HEIGHT, ResourceFormat::RGBA16Float, 1, 1, nullptr, ResourceBindFlags::ShaderResource | ResourceBindFlags::UnorderedAccess);
}

void ShaderEditor::onLoad(RenderContext* pRenderContext)
{
    // create rasterizer state
    RasterizerState::Desc rsDesc;
    mpNoCullRastState = RasterizerState::create(rsDesc);

    // Depth test
    DepthStencilState::Desc dsDesc;
    dsDesc.setDepthEnabled(false);
    mpNoDepthDS = DepthStencilState::create(dsDesc);

    // Blend state
    BlendState::Desc blendDesc;
    mpOpaqueBS = BlendState::create(blendDesc);

    // Texture sampler
    Sampler::Desc samplerDesc;
    samplerDesc.setFilterMode(Sampler::Filter::Linear, Sampler::Filter::Linear, Sampler::Filter::Linear).setMaxAnisotropy(8);
    mpLinearSampler = Sampler::create(samplerDesc);

    // Load shaders
    mPasses.resize(MAX_PASSES);
    std::string path0Str = "E:/work/Falcor/Source/Samples/HoarahLoux/Shaders/Revision2023.slang";
    mPasses[0].mPass = FullScreenPass::create(path0Str);
    mPasses[0].mShaderPath = getFilenameFromPath(path0Str);

    std::string path1Str = "E:/work/Falcor/Source/Samples/HoarahLoux/Shaders/PathtracerPost.slang";
    mPasses[1].mPass = FullScreenPass::create(path1Str);
    mPasses[1].mShaderPath = getFilenameFromPath(path1Str);


    createFbos(DEFAULT_WIDTH, DEFAULT_HEIGHT);

    // shader constants that can be tweaked through gui
    mControllableVars.resize(MAX_CONTROLLABLE_VARS);

    // create the builtin  passes
    mBlitPass = FullScreenPass::create("E:/work/Falcor/Source/Samples/HoarahLoux/Shaders/Internal/Blit.ps.slang");
    mClearPass = FullScreenPass::create("E:/work/Falcor/Source/Samples/HoarahLoux/Shaders/Internal/Clear.ps.slang");


    // camera
    mCameras.push_back(Camera::create());
    resetCamera();

    auto camera = mCameras[0];
    mpCamCtrl = SixDoFCameraController::create(camera);
    mpCamCtrl->setCameraSpeed(mCameraSpeed);
    camera->beginFrame();


    mMaxSPP = 40960.f;

   /* mCamParams.RayOrigin = float3(0., 0., -3.);
    mCamParams.RayTarget = float3(0, 0, 0);
    mCamParams.RayDirection = glm::normalize(mCamParams.RayTarget - mCamParams.RayOrigin);
    mCamParams.Right = glm::normalize(glm::cross(float3(0, 1, 0), mCamParams.RayDirection));
    mCamParams.Speed = 0.1f;*/

    createDebugResources();
}

void ShaderEditor::setCommonVars(FullScreenPass::SharedPtr& pass, float w, float h)
{
    pass["ToyCB"]["iResolution"] = float2(w, h);

    mTime += (float)gpFramework->getGlobalClock().getDelta();


    pass["ToyCB"]["iGlobalTime"] = mTime;

    if (pass["ToyCB"].findMember("iFrame").isValid())
    {
        pass["ToyCB"]["iFrame"] = mFrame;
    }

    mFrame++;


    //pass["ToyCB"]["iTimeDelta"] = (float)gpFramework->getGlobalClock().getRealTimeDelta();
    if (pass.getRootVar().findMember("iChannel0Sampler").isValid())
    {
        pass["iChannel0Sampler"] = mpLinearSampler;
    }
    if (pass.getRootVar().findMember("iChannel0").isValid())
    {
        pass["iChannel0"] = mpTex;
    }

    // camera related
    /*if (pass.getRootVar().findMember("RayOrigin").isValid())
    {
        pass["RayOrigin"] = mCamParams.RayOrigin;
    }
    if (pass.getRootVar().findMember("RayDirection").isValid())
    {
        pass["RayDirection"] = mCamParams.RayDirection;
    }*/

    if (pass["ToyCB"].findMember("RayOrigin").isValid())
    {
        pass["ToyCB"]["RayOrigin"] = mCameras[0]->getPosition();
    }

    if (pass["ToyCB"].findMember("RayTarget").isValid())
    {
        pass["ToyCB"]["RayTarget"] = mCameras[0]->getTarget();
    }

    if (pass["ToyCB"].findMember("UpVector").isValid())
    {
        pass["ToyCB"]["UpVector"] = mCameras[0]->getUpVector();
    }


    if (pass["ToyCB"].findMember("iCameraDirty").isValid())
    {
        pass["ToyCB"]["iCameraDirty"] = mCameraDirty ? 1.f : 0.f;
    }

    if (pass["ToyCB"].findMember("iAccumulationRestart").isValid())
    {
        pass["ToyCB"]["iAccumulationRestart"] = mAccumulationRestart ? 1.f : 0.f;
    }

    if (pass["ToyCB"].findMember("iMaxSPP").isValid())
    {
        pass["ToyCB"]["iMaxSPP"] = mMaxSPP;
    }
    
    // set render target of previous passes as SRV
    for (int i = 0; i < MAX_PASSES; ++i)
    {
        // check if the shader of this pass contains: iPass0Output, iPass1Output ...
        std::string varName = "iPass" + std::to_string(i) + "Output";
        if (pass.getRootVar().findMember(varName).isValid())
        {
            pass[varName] = mPasses[i].mFbo->getColorTexture(0);
        }
    }


    // debug
    if (pass.getRootVar().findMember("debugTexture").isValid())
    {
        pass["debugTexture"] = mDebugTexture;
    }
}

void ShaderEditor::executeBlitPass(RenderContext* pRenderContext, Texture::SharedPtr srcTexture, Fbo::SharedPtr dstFbo, float w, float h)
{
    mBlitPass["iChannel0Sampler"] = mpLinearSampler;
    mBlitPass["iChannel0"] = srcTexture;
    mBlitPass["CB"]["iResolution"] = float2(w, h);

    mBlitPass->execute(pRenderContext, dstFbo);
}

void ShaderEditor::executeClearPass(RenderContext* pRenderContext, Fbo::SharedPtr Fbo)
{
    if (mNeedsClear)
    {
        for (int i = 0; i < mPasses.size(); ++i)
        {
            if (mPasses[i].mActive)
            {
                mClearPass->execute(pRenderContext, mPasses[i].mFbo);
            }
        }
        mNeedsClear = false;
    }
}

void ShaderEditor::onFrameRender(RenderContext* pRenderContext, const Fbo::SharedPtr& pTargetFbo)
{
    mCameraDirty = mpCamCtrl->update();

    mAccumulationRestart = mAccumulationRestart || (mPrevCameraDirty && !mCameraDirty);

    if (mAccumulationRestart) mSppAccumulated = 0;

    mPrevCameraDirty = mCameraDirty;

    executeClearPass(pRenderContext, pTargetFbo);
    
    // iResolution
    float width = (float)pTargetFbo->getWidth();
    float height = (float)pTargetFbo->getHeight();

    int lastPass = -1;
    for (int i = 0; i < mPasses.size(); ++i)
    {
        if (mPasses[i].mActive && mPasses[i].mShaderPath.length() > 0)
        {
            setCommonVars(mPasses[i].mPass, width, height);
            // run final pass
            mPasses[i].mPass->execute(pRenderContext, mPasses[i].mFbo);
            lastPass = i;
        }
    }


    Texture::SharedPtr passOutput = nullptr;
    if(lastPass >= 0)
        passOutput = mPasses[lastPass].mFbo->getColorTexture(0);
    // copy the result of the last pass to the target fbo
    // blit is not working with mipmapped textures
    //pRenderContext->blit(passOutput->getSRV(), pTargetFbo->getRenderTargetView(0));

    executeBlitPass(pRenderContext, passOutput, pTargetFbo, width, height);

    mAccumulationRestart = false;
    mSppAccumulated++;
}


// actually replace current pass atm
void ShaderEditor::setPass(const int index)
{
    if (index >= mPasses.size())
    {
        msgBox(fmt::format("Too many passes!\n"));
        return;
    }

    std::filesystem::path path;
    FileDialogFilter filter("slang");
    FileDialogFilterVec filterVec;
    filterVec.push_back(filter);

    if (openFileDialog(filterVec, path))
    {
        mPasses[index].mPass = FullScreenPass::create(path);
        std::string pathStr = path.string();
        mPasses[index].mShaderPath = getFilenameFromPath(path.string());
        mPasses[index].mActive = true;
    }
}


void ShaderEditor::onGuiRender(Gui* pGui)
{
    Gui::Window w(pGui, "ShaderEditor", { 300, 500 }, { 0, 0 });

    // camera
    {
        float3 camPos = mCameras[0]->getPosition();
        std::string camPosStr = "CamPos: " + std::to_string(camPos.x) + ", " +
            std::to_string(camPos.y) + ", " + std::to_string(camPos.z);
        w.text(camPosStr, false);

        float3 camTarget = mCameras[0]->getTarget();
        std::string camTargetStr = "CamTarget: " + std::to_string(camTarget.x) + ", " +
            std::to_string(camTarget.y) + ", " + std::to_string(camTarget.z);
        w.text(camTargetStr, false);

        float3 camUp = mCameras[0]->getUpVector();
        std::string camUpStr = "CamUp: " + std::to_string(camUp.x) + ", " +
            std::to_string(camUp.y) + ", " + std::to_string(camUp.z);
        w.text(camUpStr, false);

        w.var("Camera Pos", camPos);
        mCameras[0]->setPosition(camPos);

    }

    // passes
    {
        auto loadGroup = w.group("Setup Passes");
        if (loadGroup.button("Pass0")) setPass(0);
        loadGroup.text(mPasses[0].mShaderPath, true);

        if (loadGroup.button("Pass1")) setPass(1);
        loadGroup.text(mPasses[1].mShaderPath, true);

        if (loadGroup.button("Pass2")) setPass(2);
        loadGroup.text(mPasses[2].mShaderPath, true);

        if (loadGroup.button("Pass3"))  setPass(3);
        loadGroup.text(mPasses[3].mShaderPath, true);

        loadGroup.checkbox("Activate Pass0", mPasses[0].mActive, false);
        loadGroup.checkbox("Activate Pass1", mPasses[1].mActive, false);
        loadGroup.checkbox("Activate Pass2", mPasses[2].mActive, false);
        loadGroup.checkbox("Activate Pass3", mPasses[3].mActive, false);
    }

   /**/
    
    if (w.button("Reset Time"))
    {
        mNeedsClear = true;
        mTime = 0.f;
        mFrame = 0.f;
    }
    w.slider("iGlobalTime", mTime, 0.f, 180.f);

    std::string numSppStr = "SPP Accumulated: " + std::to_string(mSppAccumulated);
    w.text(numSppStr, false);

    std::string msg = gpFramework->getFrameRate().getMsg(gpFramework->isVsyncEnabled());
    w.text(msg, false);


    w.slider("var0", mControllableVars[0], -1.f, 1.f);
    w.slider("var1", mControllableVars[1], -1.f, 1.f);
    w.slider("var2", mControllableVars[2], -1.f, 1.f);
    w.slider("var3", mControllableVars[3], -1.f, 1.f);
    w.slider("var4", mControllableVars[4], -1.f, 1.f);


    /*if (mDrawWireframe == false)
    {
        Gui::DropdownList cullList;
        cullList.push_back({ (uint32_t)RasterizerState::CullMode::None, "No Culling" });
        cullList.push_back({ (uint32_t)RasterizerState::CullMode::Back, "Backface Culling" });
        cullList.push_back({ (uint32_t)RasterizerState::CullMode::Front, "Frontface Culling" });
        w.dropdown("Cull Mode", cullList, (uint32_t&)mCullMode);
    }*/

    //Gui::DropdownList cameraDropdown;
    //cameraDropdown.push_back({ (uint32_t)Scene::CameraControllerType::FirstPerson, "First-Person" });
    //cameraDropdown.push_back({ (uint32_t)Scene::CameraControllerType::Orbiter, "Orbiter" });
    //cameraDropdown.push_back({ (uint32_t)Scene::CameraControllerType::SixDOF, "6-DoF" });

    //if (w.dropdown("Camera Type", cameraDropdown, (uint32_t&)mCameraType)) setCamController();
    //if (mpScene) mpScene->renderUI(w);

    if (w.button("Set texture 0"))
    {
        mpTex = loadImage();
    }

    if (w.button("Reset Camera"))
    {
        resetCamera();
    }
    w.text(mTexPath, true);
}


void ShaderEditor::onShutdown()
{
}

bool ShaderEditor::onKeyEvent(const KeyboardEvent& keyEvent)
{
    bool bHandled = false;
    {
        if(keyEvent.type == KeyboardEvent::Type::KeyPressed)
        {
            switch(keyEvent.key)
            {
            case Input::Key::Space:
            {
                gpFramework->pauseRenderer(!gpFramework->isRendererPaused());
                break;
            }
            case Input::Key::Enter:
            {
                HotReloadFlags reloaded = HotReloadFlags::None;
                if (Program::reloadAllPrograms()) reloaded |= HotReloadFlags::Program;
                this->onHotReload(reloaded);
                break;
            }
            // for making skybox for espen, changing view direction to next cube face
            case Input::Key::J:
            {
                RotateCamera90AroundUp();
                mAccumulationRestart = true;
                break;
            }
            case Input::Key::K:
            {
                RotateCamera90AroundRight();
                mAccumulationRestart = true;
                break;
            }
            
            default:
                bHandled = false;
            }
        }
    }

    // for camera
    {
        mpCamCtrl->onKeyEvent(keyEvent);
    }
    return bHandled;
}

bool ShaderEditor::onMouseEvent(const MouseEvent& mouseEvent)
{
    bool handled = false;
   
    mpCamCtrl->onMouseEvent(mouseEvent);

    return handled;
}

void ShaderEditor::onResizeSwapChain(uint32_t width, uint32_t height)
{
    mAspectRatio = (float(width) / float(height));

    createFbos(width, height);
}

#ifdef _WIN32
int WINAPI WinMain(_In_ HINSTANCE hInstance, _In_opt_ HINSTANCE hPrevInstance, _In_ LPSTR lpCmdLine, _In_ int nShowCmd)
#else
int main(int argc, char** argv)
#endif
{
    ShaderEditor::UniquePtr pRenderer = std::make_unique<ShaderEditor>();
    SampleConfig config;
    config.windowDesc.width = DEFAULT_WIDTH;
    config.windowDesc.height = DEFAULT_HEIGHT;
    config.deviceDesc.enableVsync = true;
    config.windowDesc.resizableWindow = true;
    config.windowDesc.title = "ShaderEditor";
#ifdef _WIN32
    Sample::run(config, pRenderer);
#else
    config.argc = (uint32_t)argc;
    config.argv = argv;
    Sample::run(config, pRenderer);
#endif
    return 0;
}
