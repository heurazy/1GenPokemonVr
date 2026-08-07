#ifdef __ANDROID__
#include <jni.h>
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <dlfcn.h>
#define XR_USE_PLATFORM_ANDROID
#define XR_USE_GRAPHICS_API_OPENGL_ES
#define GEN1_EXPORT __attribute__((visibility("default")))
#else
#include <windows.h>
#include <Unknwn.h>
#include <GL/gl.h>
#ifndef XR_USE_PLATFORM_WIN32
#define XR_USE_PLATFORM_WIN32
#endif
#ifndef XR_USE_GRAPHICS_API_OPENGL
#define XR_USE_GRAPHICS_API_OPENGL
#endif
#define GEN1_EXPORT __declspec(dllexport)
#endif

// Microsoft's legacy OpenGL 1.1 header defines APIENTRY but, depending on
// the Windows SDK version, not the pointer spelling used by newer OpenGL
// extension typedefs.
#if !defined(__ANDROID__) && !defined(APIENTRYP)
#define APIENTRYP APIENTRY *
#endif

#include <openxr/openxr.h>
#include <openxr/openxr_platform.h>

#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <initializer_list>
#include <string>
#include <thread>
#include <utility>
#include <vector>
#include <chrono>

namespace {

constexpr GLenum GL_SRGB8_ALPHA8_VALUE = 0x8C43;
constexpr GLenum GL_RGBA8_VALUE = 0x8058;
constexpr GLenum GL_READ_FRAMEBUFFER_VALUE = 0x8CA8;
constexpr GLenum GL_DRAW_FRAMEBUFFER_VALUE = 0x8CA9;
constexpr GLenum GL_READ_FRAMEBUFFER_BINDING_VALUE = 0x8CAA;
constexpr GLenum GL_DRAW_FRAMEBUFFER_BINDING_VALUE = 0x8CA6;
constexpr GLenum GL_COLOR_ATTACHMENT0_VALUE = 0x8CE0;
constexpr GLenum GL_FRAMEBUFFER_COMPLETE_VALUE = 0x8CD5;

#ifdef __ANDROID__
void* loveLibrary = nullptr;
jobject androidActivity = nullptr;

void* loveSymbol(const char* name) {
  // liblove.so is loaded by Java with RTLD_LOCAL, so its public SDL symbols
  // are not necessarily visible through RTLD_DEFAULT on Quest.  Acquire an
  // explicit handle to the already-loaded library and resolve against it.
  if (!loveLibrary) {
    loveLibrary = dlopen("liblove.so", RTLD_NOW | RTLD_NOLOAD);
    if (!loveLibrary) loveLibrary = dlopen("liblove.so", RTLD_NOW);
  }
  return loveLibrary ? dlsym(loveLibrary, name) : nullptr;
}

using PFNGLGENFRAMEBUFFERSPROC = void(*)(GLsizei, GLuint*);
using PFNGLDELETEFRAMEBUFFERSPROC = void(*)(GLsizei, const GLuint*);
using PFNGLBINDFRAMEBUFFERPROC = void(*)(GLenum, GLuint);
using PFNGLFRAMEBUFFERTEXTURE2DPROC =
    void(*)(GLenum, GLenum, GLenum, GLuint, GLint);
using PFNGLCHECKFRAMEBUFFERSTATUSPROC = GLenum(*)(GLenum);
using PFNGLBLITFRAMEBUFFERPROC =
    void(*)(GLint, GLint, GLint, GLint, GLint, GLint, GLint, GLint,
            GLbitfield, GLenum);
#else
using PFNGLGENFRAMEBUFFERSPROC = void(APIENTRYP)(GLsizei, GLuint*);
using PFNGLDELETEFRAMEBUFFERSPROC = void(APIENTRYP)(GLsizei, const GLuint*);
using PFNGLBINDFRAMEBUFFERPROC = void(APIENTRYP)(GLenum, GLuint);
using PFNGLFRAMEBUFFERTEXTURE2DPROC =
    void(APIENTRYP)(GLenum, GLenum, GLenum, GLuint, GLint);
using PFNGLCHECKFRAMEBUFFERSTATUSPROC = GLenum(APIENTRYP)(GLenum);
using PFNGLBLITFRAMEBUFFERPROC =
    void(APIENTRYP)(GLint, GLint, GLint, GLint, GLint, GLint, GLint, GLint,
                    GLbitfield, GLenum);
#endif

struct GLFunctions {
  PFNGLGENFRAMEBUFFERSPROC genFramebuffers = nullptr;
  PFNGLDELETEFRAMEBUFFERSPROC deleteFramebuffers = nullptr;
  PFNGLBINDFRAMEBUFFERPROC bindFramebuffer = nullptr;
  PFNGLFRAMEBUFFERTEXTURE2DPROC framebufferTexture2D = nullptr;
  PFNGLCHECKFRAMEBUFFERSTATUSPROC checkFramebufferStatus = nullptr;
  PFNGLBLITFRAMEBUFFERPROC blitFramebuffer = nullptr;
};

struct Swapchain {
  XrSwapchain handle = XR_NULL_HANDLE;
  int32_t width = 0;
  int32_t height = 0;
#ifdef __ANDROID__
  std::vector<XrSwapchainImageOpenGLESKHR> images;
#else
  std::vector<XrSwapchainImageOpenGLKHR> images;
#endif
  uint32_t acquiredIndex = 0;
  bool acquired = false;
};

XrInstance instance = XR_NULL_HANDLE;
XrSystemId systemId = XR_NULL_SYSTEM_ID;
XrSession session = XR_NULL_HANDLE;
XrSpace localSpace = XR_NULL_HANDLE;
XrSessionState sessionState = XR_SESSION_STATE_UNKNOWN;
bool sessionRunning = false;
bool frameBegun = false;
XrFrameState frameState{XR_TYPE_FRAME_STATE};
std::array<XrViewConfigurationView, 2> configViews{{
    {XR_TYPE_VIEW_CONFIGURATION_VIEW},
    {XR_TYPE_VIEW_CONFIGURATION_VIEW},
}};
std::array<XrView, 2> locatedViews{{
    {XR_TYPE_VIEW},
    {XR_TYPE_VIEW},
}};
std::array<Swapchain, 2> swapchains;
Swapchain uiSwapchain;
Swapchain battleSwapchain;
Swapchain enemySwapchain;
Swapchain attackSwapchain;
Swapchain playerSwapchain;
Swapchain hudSwapchain;
XrPosef uiPose{{0, 0, 0, 1}, {0, 0, 0}};
XrPosef battlePose{{0, 0, 0, 1}, {0, 0, 0}};
XrPosef enemyPose{{0, 0, 0, 1}, {0, 0, 0}};
XrPosef attackPose{{0, 0, 0, 1}, {0, 0, 0}};
XrPosef playerPose{{0, 0, 0, 1}, {0, 0, 0}};
XrPosef hudPose{{0, 0, 0, 1}, {0, 0, 0}};
bool uiAnchorValid = false;
bool uiCaptured = false;
bool battleAnchorValid = false;
bool battleCaptured = false;
bool enemyCaptured = false;
bool attackCaptured = false;
bool playerCaptured = false;
bool hudCaptured = false;
bool battleWasVisible = false;
std::string lastError;
GLFunctions gl;

// Quest display-rate control. The Lua render loop must not impose its own
// 60 FPS sleep while xrWaitFrame is active, but the runtime also needs an
// explicit preferred refresh rate or it may keep the system default. Keep
// the request pending across READY/STOPPING transitions and always snap it
// to a rate the current runtime actually enumerates.
bool hasDisplayRefreshRate = false;
PFN_xrEnumerateDisplayRefreshRatesFB enumerateDisplayRefreshRates = nullptr;
PFN_xrGetDisplayRefreshRateFB getDisplayRefreshRate = nullptr;
PFN_xrRequestDisplayRefreshRateFB requestDisplayRefreshRate = nullptr;
float preferredDisplayRefreshRate = 90.0f;
float activeDisplayRefreshRate = 0.0f;

XrVector3f rotateVector(const XrQuaternionf& q, const XrVector3f& v);
bool endEmptyFrame();

// One semantic action set covers every controller. Interaction-profile
// bindings below translate device-specific paths (Touch, Index, Vive, WMR,
// simple controllers) into these stable game actions.
XrActionSet inputActionSet = XR_NULL_HANDLE;
XrAction moveAction = XR_NULL_HANDLE;
XrAction turnAction = XR_NULL_HANDLE;
XrAction aAction = XR_NULL_HANDLE;
XrAction bAction = XR_NULL_HANDLE;
XrAction startAction = XR_NULL_HANDLE;
XrAction selectAction = XR_NULL_HANDLE;
XrAction recenterAction = XR_NULL_HANDLE;
XrAction pointerPoseAction = XR_NULL_HANDLE;
XrAction pointerClickAction = XR_NULL_HANDLE;
XrAction pointerTriggerAction = XR_NULL_HANDLE;
XrAction squeezeAction = XR_NULL_HANDLE;
XrSpace pointerAimSpace = XR_NULL_HANDLE;
XrAction gripPoseAction = XR_NULL_HANDLE;
std::array<XrPath, 2> handPaths{{XR_NULL_PATH, XR_NULL_PATH}};
std::array<XrSpace, 2> gripSpaces{{XR_NULL_HANDLE, XR_NULL_HANDLE}};
std::array<XrPosef, 2> gripPoses{};
std::array<bool, 2> gripActive{{false, false}};
bool pointerHitActive = false;
float pointerHitX = 0.5f;
float pointerHitY = 0.5f;

const char* resultName(XrResult result) {
  switch (result) {
    case XR_ERROR_VALIDATION_FAILURE: return "XR_ERROR_VALIDATION_FAILURE";
    case XR_ERROR_RUNTIME_FAILURE: return "XR_ERROR_RUNTIME_FAILURE";
    case XR_ERROR_OUT_OF_MEMORY: return "XR_ERROR_OUT_OF_MEMORY";
    case XR_ERROR_API_VERSION_UNSUPPORTED:
      return "XR_ERROR_API_VERSION_UNSUPPORTED";
    case XR_ERROR_INITIALIZATION_FAILED: return "XR_ERROR_INITIALIZATION_FAILED";
    case XR_ERROR_FUNCTION_UNSUPPORTED: return "XR_ERROR_FUNCTION_UNSUPPORTED";
    case XR_ERROR_EXTENSION_NOT_PRESENT: return "XR_ERROR_EXTENSION_NOT_PRESENT";
    case XR_ERROR_LIMIT_REACHED: return "XR_ERROR_LIMIT_REACHED";
    case XR_ERROR_SIZE_INSUFFICIENT: return "XR_ERROR_SIZE_INSUFFICIENT";
    case XR_ERROR_HANDLE_INVALID: return "XR_ERROR_HANDLE_INVALID";
    case XR_ERROR_INSTANCE_LOST: return "XR_ERROR_INSTANCE_LOST";
    case XR_ERROR_RUNTIME_UNAVAILABLE: return "XR_ERROR_RUNTIME_UNAVAILABLE";
    default: return nullptr;
  }
}

void setError(const char* where, XrResult result) {
  char resultText[XR_MAX_RESULT_STRING_SIZE] = {};
  if (instance != XR_NULL_HANDLE) {
    xrResultToString(instance, result, resultText);
  }
  lastError = std::string(where) + " failed";
  if (resultText[0]) {
    lastError += std::string(": ") + resultText;
  } else if (const char* name = resultName(result)) {
    lastError += std::string(": ") + name;
  } else {
    lastError += ": result " + std::to_string(static_cast<int32_t>(result));
  }
}

bool xrOK(const char* where, XrResult result) {
  if (XR_SUCCEEDED(result)) return true;
  setError(where, result);
  return false;
}

template <typename T>
bool loadInstanceFunction(const char* name, T& out) {
  return XR_SUCCEEDED(xrGetInstanceProcAddr(
      instance, name, reinterpret_cast<PFN_xrVoidFunction*>(&out))) && out;
}

bool makeAction(XrAction& action, XrActionType type, const char* name,
                const char* label) {
  XrActionCreateInfo info{XR_TYPE_ACTION_CREATE_INFO};
  info.actionType = type;
  std::strncpy(info.actionName, name, XR_MAX_ACTION_NAME_SIZE - 1);
  std::strncpy(info.localizedActionName, label,
               XR_MAX_LOCALIZED_ACTION_NAME_SIZE - 1);
  return xrOK("xrCreateAction",
              xrCreateAction(inputActionSet, &info, &action));
}

bool makeHandPoseAction() {
  if (!xrOK("xrStringToPath(left hand)",
            xrStringToPath(instance, "/user/hand/left", &handPaths[0])) ||
      !xrOK("xrStringToPath(right hand)",
            xrStringToPath(instance, "/user/hand/right", &handPaths[1]))) {
    return false;
  }
  XrActionCreateInfo info{XR_TYPE_ACTION_CREATE_INFO};
  info.actionType = XR_ACTION_TYPE_POSE_INPUT;
  std::strncpy(info.actionName, "controller_grip",
               XR_MAX_ACTION_NAME_SIZE - 1);
  std::strncpy(info.localizedActionName, "Tracked controllers",
               XR_MAX_LOCALIZED_ACTION_NAME_SIZE - 1);
  info.countSubactionPaths = 2;
  info.subactionPaths = handPaths.data();
  return xrOK("xrCreateAction(controller grip)",
              xrCreateAction(inputActionSet, &info, &gripPoseAction));
}

void suggestBindings(
    const char* profile,
    std::initializer_list<std::pair<XrAction, const char*>> requested) {
  XrPath profilePath = XR_NULL_PATH;
  if (XR_FAILED(xrStringToPath(instance, profile, &profilePath))) return;
  std::vector<XrActionSuggestedBinding> bindings;
  bindings.reserve(requested.size());
  for (const auto& entry : requested) {
    XrPath path = XR_NULL_PATH;
    if (XR_SUCCEEDED(xrStringToPath(instance, entry.second, &path))) {
      bindings.push_back({entry.first, path});
    }
  }
  XrInteractionProfileSuggestedBinding suggested{
      XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING};
  suggested.interactionProfile = profilePath;
  suggested.countSuggestedBindings =
      static_cast<uint32_t>(bindings.size());
  suggested.suggestedBindings = bindings.data();
  // Profiles are optional. A runtime is allowed to reject profiles it does
  // not expose; the remaining profiles and LOVE gamepads still work.
  xrSuggestInteractionProfileBindings(instance, &suggested);
}

bool createInputActions() {
  XrActionSetCreateInfo setInfo{XR_TYPE_ACTION_SET_CREATE_INFO};
  std::strncpy(setInfo.actionSetName, "pokemon", XR_MAX_ACTION_SET_NAME_SIZE - 1);
  std::strncpy(setInfo.localizedActionSetName, "Pokemon VR Controls",
               XR_MAX_LOCALIZED_ACTION_SET_NAME_SIZE - 1);
  setInfo.priority = 0;
  if (!xrOK("xrCreateActionSet",
            xrCreateActionSet(instance, &setInfo, &inputActionSet))) {
    return false;
  }
  if (!makeAction(moveAction, XR_ACTION_TYPE_VECTOR2F_INPUT, "move", "Move") ||
      !makeAction(turnAction, XR_ACTION_TYPE_VECTOR2F_INPUT, "turn", "Orbit camera") ||
      !makeAction(aAction, XR_ACTION_TYPE_BOOLEAN_INPUT, "button_a", "Confirm") ||
      !makeAction(bAction, XR_ACTION_TYPE_BOOLEAN_INPUT, "button_b", "Cancel") ||
      !makeAction(startAction, XR_ACTION_TYPE_BOOLEAN_INPUT, "start", "Start") ||
      !makeAction(selectAction, XR_ACTION_TYPE_BOOLEAN_INPUT, "select", "Select") ||
      !makeAction(recenterAction, XR_ACTION_TYPE_BOOLEAN_INPUT, "recenter", "Recenter") ||
      !makeAction(pointerPoseAction, XR_ACTION_TYPE_POSE_INPUT,
                  "menu_pointer", "Menu pointer") ||
      !makeAction(pointerClickAction, XR_ACTION_TYPE_BOOLEAN_INPUT,
                  "pointer_click", "Point and confirm") ||
      !makeAction(pointerTriggerAction, XR_ACTION_TYPE_FLOAT_INPUT,
                  "pointer_trigger", "Pointer trigger") ||
      !makeAction(squeezeAction, XR_ACTION_TYPE_FLOAT_INPUT,
                  "button_squeeze", "Cancel with grip") ||
      !makeHandPoseAction()) {
    return false;
  }

  suggestBindings("/interaction_profiles/khr/simple_controller", {
      {gripPoseAction, "/user/hand/left/input/grip/pose"},
      {gripPoseAction, "/user/hand/right/input/grip/pose"},
      {pointerPoseAction, "/user/hand/right/input/aim/pose"},
      {pointerClickAction, "/user/hand/right/input/select/click"},
      {bAction, "/user/hand/right/input/menu/click"},
      {startAction, "/user/hand/left/input/menu/click"},
      {selectAction, "/user/hand/left/input/select/click"},
  });
  suggestBindings("/interaction_profiles/oculus/touch_controller", {
      {gripPoseAction, "/user/hand/left/input/grip/pose"},
      {gripPoseAction, "/user/hand/right/input/grip/pose"},
      {moveAction, "/user/hand/left/input/thumbstick"},
      {turnAction, "/user/hand/right/input/thumbstick"},
      {aAction, "/user/hand/right/input/a/click"},
      {pointerPoseAction, "/user/hand/right/input/aim/pose"},
      {pointerTriggerAction, "/user/hand/right/input/trigger/value"},
      {bAction, "/user/hand/right/input/b/click"},
      {squeezeAction, "/user/hand/right/input/squeeze/value"},
      {startAction, "/user/hand/left/input/menu/click"},
      {selectAction, "/user/hand/left/input/y/click"},
      {recenterAction, "/user/hand/right/input/thumbstick/click"},
  });
  // Quest 3/3S report Touch Plus as its own interaction profile instead of
  // emulating the older Oculus Touch profile.  Meta firmware has shipped
  // both spellings while the extension was being standardized, so suggest
  // the same semantic bindings for both; unsupported profiles are ignored.
  const auto suggestTouchPlus = [](const char* profile) {
    suggestBindings(profile, {
        {gripPoseAction, "/user/hand/left/input/grip/pose"},
        {gripPoseAction, "/user/hand/right/input/grip/pose"},
        {moveAction, "/user/hand/left/input/thumbstick"},
        {turnAction, "/user/hand/right/input/thumbstick"},
        {aAction, "/user/hand/right/input/a/click"},
        {pointerPoseAction, "/user/hand/right/input/aim/pose"},
        {pointerTriggerAction, "/user/hand/right/input/trigger/value"},
        {bAction, "/user/hand/right/input/b/click"},
        {squeezeAction, "/user/hand/right/input/squeeze/value"},
        {startAction, "/user/hand/left/input/menu/click"},
        {selectAction, "/user/hand/left/input/y/click"},
        {recenterAction, "/user/hand/right/input/thumbstick/click"},
    });
  };
  suggestTouchPlus("/interaction_profiles/meta/touch_plus_controller");
  suggestTouchPlus("/interaction_profiles/meta/touch_controller_plus");
  suggestBindings("/interaction_profiles/valve/index_controller", {
      {gripPoseAction, "/user/hand/left/input/grip/pose"},
      {gripPoseAction, "/user/hand/right/input/grip/pose"},
      {moveAction, "/user/hand/left/input/thumbstick"},
      {turnAction, "/user/hand/right/input/thumbstick"},
      {aAction, "/user/hand/right/input/a/click"},
      {pointerPoseAction, "/user/hand/right/input/aim/pose"},
      {pointerTriggerAction, "/user/hand/right/input/trigger/value"},
      {bAction, "/user/hand/right/input/b/click"},
      {squeezeAction, "/user/hand/right/input/squeeze/value"},
      {startAction, "/user/hand/left/input/b/click"},
      {selectAction, "/user/hand/left/input/a/click"},
      {recenterAction, "/user/hand/right/input/thumbstick/click"},
  });
  suggestBindings("/interaction_profiles/htc/vive_controller", {
      {gripPoseAction, "/user/hand/left/input/grip/pose"},
      {gripPoseAction, "/user/hand/right/input/grip/pose"},
      {moveAction, "/user/hand/left/input/trackpad"},
      {turnAction, "/user/hand/right/input/trackpad"},
      {pointerPoseAction, "/user/hand/right/input/aim/pose"},
      {pointerClickAction, "/user/hand/right/input/trigger/click"},
      {bAction, "/user/hand/right/input/squeeze/click"},
      {startAction, "/user/hand/right/input/menu/click"},
      {selectAction, "/user/hand/left/input/menu/click"},
      {recenterAction, "/user/hand/right/input/trackpad/click"},
  });
  suggestBindings("/interaction_profiles/microsoft/motion_controller", {
      {gripPoseAction, "/user/hand/left/input/grip/pose"},
      {gripPoseAction, "/user/hand/right/input/grip/pose"},
      {moveAction, "/user/hand/left/input/thumbstick"},
      {turnAction, "/user/hand/right/input/thumbstick"},
      {pointerPoseAction, "/user/hand/right/input/aim/pose"},
      {pointerTriggerAction, "/user/hand/right/input/trigger/value"},
      {bAction, "/user/hand/right/input/squeeze/click"},
      {startAction, "/user/hand/right/input/menu/click"},
      {selectAction, "/user/hand/left/input/menu/click"},
      {recenterAction, "/user/hand/right/input/thumbstick/click"},
  });
  return true;
}

void updateGripPoses() {
  for (size_t hand = 0; hand < gripSpaces.size(); ++hand) {
    gripActive[hand] = false;
    if (gripSpaces[hand] == XR_NULL_HANDLE) continue;
    XrSpaceLocation location{XR_TYPE_SPACE_LOCATION};
    if (XR_FAILED(xrLocateSpace(gripSpaces[hand], localSpace,
                                frameState.predictedDisplayTime, &location))) {
      continue;
    }
    const XrSpaceLocationFlags valid = XR_SPACE_LOCATION_POSITION_VALID_BIT |
                                       XR_SPACE_LOCATION_ORIENTATION_VALID_BIT;
    if ((location.locationFlags & valid) == valid) {
      gripPoses[hand] = location.pose;
      gripActive[hand] = true;
    }
  }
}

uint32_t controllerProfile(size_t hand) {
  if (hand >= handPaths.size() || handPaths[hand] == XR_NULL_PATH) return 0;
  XrInteractionProfileState state{XR_TYPE_INTERACTION_PROFILE_STATE};
  if (XR_FAILED(xrGetCurrentInteractionProfile(session, handPaths[hand],
                                                &state)) ||
      state.interactionProfile == XR_NULL_PATH) {
    return 0;
  }
  uint32_t length = 0;
  if (XR_FAILED(xrPathToString(instance, state.interactionProfile, 0,
                               &length, nullptr)) || length == 0) return 0;
  std::string path(length, '\0');
  if (XR_FAILED(xrPathToString(instance, state.interactionProfile, length,
                               &length, path.data()))) return 0;
  if (path.find("oculus") != std::string::npos ||
      path.find("meta") != std::string::npos) return 1;      // Quest/Touch
  if (path.find("valve") != std::string::npos) return 2;    // Index
  if (path.find("vive") != std::string::npos) return 3;     // Vive/Cosmos
  if (path.find("microsoft") != std::string::npos ||
      path.find("hp") != std::string::npos) return 4;       // WMR
  if (path.find("pico") != std::string::npos ||
      path.find("bytedance") != std::string::npos) return 5;// Pico
  return 0;
}

bool intersectUIPanel(const XrVector3f& worldOrigin,
                      const XrVector3f& worldDirection) {
  const XrQuaternionf inverse{-uiPose.orientation.x, -uiPose.orientation.y,
                              -uiPose.orientation.z, uiPose.orientation.w};
  const XrVector3f delta{worldOrigin.x - uiPose.position.x,
                         worldOrigin.y - uiPose.position.y,
                         worldOrigin.z - uiPose.position.z};
  const XrVector3f origin = rotateVector(inverse, delta);
  const XrVector3f direction = rotateVector(inverse, worldDirection);
  if (std::abs(direction.z) < 0.0001f) return false;
  const float distance = -origin.z / direction.z;
  if (distance <= 0) return false;
  const float hitX = origin.x + direction.x * distance;
  const float hitY = origin.y + direction.y * distance;
  constexpr float width = 1.15f;
  constexpr float height = 1.035f;
  pointerHitX = hitX / width + 0.5f;
  pointerHitY = 0.5f - hitY / height;
  pointerHitActive = pointerHitX >= 0 && pointerHitX <= 1 &&
                     pointerHitY >= 0 && pointerHitY <= 1;
  return pointerHitActive;
}

void updatePointerHit() {
  pointerHitActive = false;
  if (!uiAnchorValid) return;

  // Prefer the right-hand aim pose for a true laser pointer.
  if (pointerAimSpace != XR_NULL_HANDLE) {
    XrSpaceLocation location{XR_TYPE_SPACE_LOCATION};
    const XrSpaceLocationFlags valid =
        XR_SPACE_LOCATION_POSITION_VALID_BIT |
        XR_SPACE_LOCATION_ORIENTATION_VALID_BIT;
    if (XR_SUCCEEDED(xrLocateSpace(pointerAimSpace, localSpace,
                                   frameState.predictedDisplayTime,
                                   &location)) &&
        (location.locationFlags & valid) == valid) {
      const XrVector3f direction =
          rotateVector(location.pose.orientation, {0, 0, -1});
      if (intersectUIPanel(location.pose.position, direction)) return;
    }
  }

  // If a controller has only just awakened, its aim action can take a frame
  // to become active. Keep the launcher usable meanwhile with a head-gaze
  // pointer; trigger or A still performs the click.
  const XrVector3f center{
      (locatedViews[0].pose.position.x + locatedViews[1].pose.position.x) *
          0.5f,
      (locatedViews[0].pose.position.y + locatedViews[1].pose.position.y) *
          0.5f,
      (locatedViews[0].pose.position.z + locatedViews[1].pose.position.z) *
          0.5f};
  const XrVector3f direction =
      rotateVector(locatedViews[0].pose.orientation, {0, 0, -1});
  intersectUIPanel(center, direction);
}

bool actionBoolean(XrAction action) {
  XrActionStateGetInfo get{XR_TYPE_ACTION_STATE_GET_INFO};
  get.action = action;
  XrActionStateBoolean state{XR_TYPE_ACTION_STATE_BOOLEAN};
  return XR_SUCCEEDED(xrGetActionStateBoolean(session, &get, &state)) &&
         state.isActive && state.currentState;
}

float actionFloat(XrAction action) {
  XrActionStateGetInfo get{XR_TYPE_ACTION_STATE_GET_INFO};
  get.action = action;
  XrActionStateFloat state{XR_TYPE_ACTION_STATE_FLOAT};
  if (XR_SUCCEEDED(xrGetActionStateFloat(session, &get, &state)) &&
      state.isActive) {
    return state.currentState;
  }
  return 0.0f;
}

XrVector2f actionVector(XrAction action) {
  XrActionStateGetInfo get{XR_TYPE_ACTION_STATE_GET_INFO};
  get.action = action;
  XrActionStateVector2f state{XR_TYPE_ACTION_STATE_VECTOR2F};
  if (XR_SUCCEEDED(xrGetActionStateVector2f(session, &get, &state)) &&
      state.isActive) {
    return state.currentState;
  }
  return {0, 0};
}

template <typename T>
T glProc(const char* name) {
#ifdef __ANDROID__
  return reinterpret_cast<T>(eglGetProcAddress(name));
#else
  auto p = reinterpret_cast<T>(wglGetProcAddress(name));
  const auto address = reinterpret_cast<std::uintptr_t>(p);
  if (p == nullptr || address == 1 || address == 2 || address == 3 ||
      address == static_cast<std::uintptr_t>(-1)) {
    HMODULE module = GetModuleHandleA("opengl32.dll");
    p = reinterpret_cast<T>(GetProcAddress(module, name));
  }
  return p;
#endif
}

bool loadGL() {
  if (gl.blitFramebuffer) return true;
  gl.genFramebuffers =
      glProc<PFNGLGENFRAMEBUFFERSPROC>("glGenFramebuffers");
  gl.deleteFramebuffers =
      glProc<PFNGLDELETEFRAMEBUFFERSPROC>("glDeleteFramebuffers");
  gl.bindFramebuffer =
      glProc<PFNGLBINDFRAMEBUFFERPROC>("glBindFramebuffer");
  gl.framebufferTexture2D =
      glProc<PFNGLFRAMEBUFFERTEXTURE2DPROC>("glFramebufferTexture2D");
  gl.checkFramebufferStatus =
      glProc<PFNGLCHECKFRAMEBUFFERSTATUSPROC>("glCheckFramebufferStatus");
  gl.blitFramebuffer =
      glProc<PFNGLBLITFRAMEBUFFERPROC>("glBlitFramebuffer");
  if (!gl.genFramebuffers || !gl.deleteFramebuffers || !gl.bindFramebuffer ||
      !gl.framebufferTexture2D || !gl.checkFramebufferStatus ||
      !gl.blitFramebuffer) {
    lastError = "required OpenGL framebuffer functions are unavailable";
    return false;
  }
  return true;
}

void releaseAcquired() {
  for (auto& sc : swapchains) {
    if (sc.acquired && sc.handle != XR_NULL_HANDLE) {
      XrSwapchainImageReleaseInfo release{
          XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};
      xrReleaseSwapchainImage(sc.handle, &release);
      sc.acquired = false;
    }
  }
  if (uiSwapchain.acquired && uiSwapchain.handle != XR_NULL_HANDLE) {
    XrSwapchainImageReleaseInfo release{XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};
    xrReleaseSwapchainImage(uiSwapchain.handle, &release);
    uiSwapchain.acquired = false;
  }
  if (battleSwapchain.acquired &&
      battleSwapchain.handle != XR_NULL_HANDLE) {
    XrSwapchainImageReleaseInfo release{XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};
    xrReleaseSwapchainImage(battleSwapchain.handle, &release);
    battleSwapchain.acquired = false;
  }
  for (Swapchain* sc : {&enemySwapchain, &attackSwapchain,
                        &playerSwapchain, &hudSwapchain}) {
    if (sc->acquired && sc->handle != XR_NULL_HANDLE) {
      XrSwapchainImageReleaseInfo release{
          XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};
      xrReleaseSwapchainImage(sc->handle, &release);
      sc->acquired = false;
    }
  }
}

bool applyPreferredDisplayRefreshRate() {
  if (!hasDisplayRefreshRate || session == XR_NULL_HANDLE ||
      !enumerateDisplayRefreshRates || !requestDisplayRefreshRate) {
    return false;
  }
  uint32_t count = 0;
  if (XR_FAILED(enumerateDisplayRefreshRates(session, 0, &count, nullptr)) ||
      count == 0) {
    return false;
  }
  std::vector<float> rates(count);
  if (XR_FAILED(enumerateDisplayRefreshRates(
          session, count, &count, rates.data())) || count == 0) {
    return false;
  }
  float chosen = rates[0];
  float best = std::fabs(chosen - preferredDisplayRefreshRate);
  for (uint32_t i = 1; i < count; ++i) {
    const float diff = std::fabs(rates[i] - preferredDisplayRefreshRate);
    if (diff < best || (diff == best && rates[i] < chosen)) {
      chosen = rates[i];
      best = diff;
    }
  }
  if (!xrOK("xrRequestDisplayRefreshRateFB",
            requestDisplayRefreshRate(session, chosen))) {
    return false;
  }
  activeDisplayRefreshRate = chosen;
  if (getDisplayRefreshRate) {
    float current = 0.0f;
    if (XR_SUCCEEDED(getDisplayRefreshRate(session, &current)) && current > 0) {
      activeDisplayRefreshRate = current;
    }
  }
  return true;
}

bool pollEvents() {
  XrEventDataBuffer event{XR_TYPE_EVENT_DATA_BUFFER};
  while (true) {
    const XrResult result = xrPollEvent(instance, &event);
    if (result == XR_EVENT_UNAVAILABLE) return true;
    if (!xrOK("xrPollEvent", result)) return false;

    if (event.type == XR_TYPE_EVENT_DATA_DISPLAY_REFRESH_RATE_CHANGED_FB) {
      const auto* changed =
          reinterpret_cast<const XrEventDataDisplayRefreshRateChangedFB*>(&event);
      activeDisplayRefreshRate = changed->toDisplayRefreshRate;
    } else if (event.type == XR_TYPE_EVENT_DATA_SESSION_STATE_CHANGED) {
      const auto* changed =
          reinterpret_cast<const XrEventDataSessionStateChanged*>(&event);
      sessionState = changed->state;
      if (sessionState == XR_SESSION_STATE_READY && !sessionRunning) {
        XrSessionBeginInfo begin{XR_TYPE_SESSION_BEGIN_INFO};
        begin.primaryViewConfigurationType =
            XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
        if (!xrOK("xrBeginSession", xrBeginSession(session, &begin))) {
          return false;
        }
        sessionRunning = true;
        applyPreferredDisplayRefreshRate();
      } else if (sessionState == XR_SESSION_STATE_STOPPING &&
                 sessionRunning) {
        // Android can revoke immersive focus between xrBeginFrame and the
        // application's submit. Finish that frame before ending the session;
        // otherwise the runtime keeps an acquired swapchain and the next
        // immersive app can block in xrEndFrame.
        if (frameBegun && !endEmptyFrame()) return false;
        if (!xrOK("xrEndSession", xrEndSession(session))) return false;
        sessionRunning = false;
      } else if (sessionState == XR_SESSION_STATE_EXITING ||
                 sessionState == XR_SESSION_STATE_LOSS_PENDING) {
        if (frameBegun) endEmptyFrame();
        sessionRunning = false;
      }
    }
    event = {XR_TYPE_EVENT_DATA_BUFFER};
  }
}

int64_t chooseFormat() {
  uint32_t count = 0;
  if (!xrOK("xrEnumerateSwapchainFormats",
            xrEnumerateSwapchainFormats(session, 0, &count, nullptr))) {
    return 0;
  }
  std::vector<int64_t> formats(count);
  if (!xrOK("xrEnumerateSwapchainFormats",
            xrEnumerateSwapchainFormats(session, count, &count,
                                        formats.data()))) {
    return 0;
  }
  for (const auto wanted :
       {static_cast<int64_t>(GL_SRGB8_ALPHA8_VALUE),
        static_cast<int64_t>(GL_RGBA8_VALUE)}) {
    for (const auto available : formats) {
      if (available == wanted) return wanted;
    }
  }
  lastError = "OpenXR runtime exposes no RGBA8 OpenGL swapchain format";
  return 0;
}

bool createSwapchain(Swapchain& sc, int32_t width, int32_t height,
                     int64_t format) {
    sc.width = width;
    sc.height = height;
    XrSwapchainCreateInfo info{XR_TYPE_SWAPCHAIN_CREATE_INFO};
    info.usageFlags = XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT |
                      XR_SWAPCHAIN_USAGE_SAMPLED_BIT;
    info.format = format;
    info.sampleCount = 1;
    info.width = sc.width;
    info.height = sc.height;
    info.faceCount = 1;
    info.arraySize = 1;
    info.mipCount = 1;
    if (!xrOK("xrCreateSwapchain",
              xrCreateSwapchain(session, &info, &sc.handle))) {
      return false;
    }
    uint32_t count = 0;
    if (!xrOK("xrEnumerateSwapchainImages",
              xrEnumerateSwapchainImages(sc.handle, 0, &count, nullptr))) {
      return false;
    }
    sc.images.resize(count);
    for (auto& image : sc.images) {
#ifdef __ANDROID__
      image = {XR_TYPE_SWAPCHAIN_IMAGE_OPENGL_ES_KHR};
#else
      image = {XR_TYPE_SWAPCHAIN_IMAGE_OPENGL_KHR};
#endif
    }
    if (!xrOK("xrEnumerateSwapchainImages",
              xrEnumerateSwapchainImages(
                  sc.handle, count, &count,
                  reinterpret_cast<XrSwapchainImageBaseHeader*>(
                      sc.images.data())))) {
      return false;
    }
  return true;
}

bool createSwapchains() {
  const int64_t format = chooseFormat();
  if (!format) return false;
  for (size_t eye = 0; eye < swapchains.size(); ++eye) {
    if (!createSwapchain(
            swapchains[eye],
            static_cast<int32_t>(configViews[eye].recommendedImageRectWidth),
            static_cast<int32_t>(configViews[eye].recommendedImageRectHeight),
            format)) {
      return false;
    }
  }
  // Preserve the Game Boy UI's 160:144 aspect at a resolution comfortably
  // above the source art. Alpha is retained for dialog boxes over the world.
  if (!createSwapchain(uiSwapchain, 1024, 922, format)) return false;
  // The spatial battle stage contains only the 160x96 battlefield. Commands
  // remain on the independent UI layer, so the two surfaces can sit at
  // different physical depths without duplicating either image per eye.
  if (!createSwapchain(battleSwapchain, 1024, 614, format)) return false;
  if (!createSwapchain(enemySwapchain, 1024, 614, format)) return false;
  if (!createSwapchain(attackSwapchain, 1024, 614, format)) return false;
  if (!createSwapchain(playerSwapchain, 1024, 614, format)) return false;
  return createSwapchain(hudSwapchain, 1024, 614, format);
}

bool acquireSwapchain(Swapchain& sc) {
  XrSwapchainImageAcquireInfo acquire{XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO};
  if (!xrOK("xrAcquireSwapchainImage",
            xrAcquireSwapchainImage(sc.handle, &acquire,
                                    &sc.acquiredIndex))) {
    return false;
  }
  sc.acquired = true;
  XrSwapchainImageWaitInfo wait{XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO};
  wait.timeout = XR_INFINITE_DURATION;
  return xrOK("xrWaitSwapchainImage",
              xrWaitSwapchainImage(sc.handle, &wait));
}

bool acquireSwapchains() {
  for (auto& sc : swapchains) {
    if (!acquireSwapchain(sc)) {
      releaseAcquired();
      return false;
    }
  }
  if (!acquireSwapchain(uiSwapchain)) {
    releaseAcquired();
    return false;
  }
  if (!acquireSwapchain(battleSwapchain)) {
    releaseAcquired();
    return false;
  }
  for (Swapchain* sc : {&enemySwapchain, &attackSwapchain,
                        &playerSwapchain, &hudSwapchain}) {
    if (!acquireSwapchain(*sc)) {
      releaseAcquired();
      return false;
    }
  }
  uiCaptured = false;
  battleCaptured = false;
  enemyCaptured = attackCaptured = playerCaptured = hudCaptured = false;
  return true;
}

XrVector3f rotateVector(const XrQuaternionf& q, const XrVector3f& v) {
  // q * v * conjugate(q), expanded to avoid introducing a math dependency.
  const XrVector3f u{q.x, q.y, q.z};
  const float dotUV = u.x * v.x + u.y * v.y + u.z * v.z;
  const float dotUU = u.x * u.x + u.y * u.y + u.z * u.z;
  const XrVector3f cross{u.y * v.z - u.z * v.y,
                         u.z * v.x - u.x * v.z,
                         u.x * v.y - u.y * v.x};
  return {2.0f * dotUV * u.x + (q.w * q.w - dotUU) * v.x +
              2.0f * q.w * cross.x,
          2.0f * dotUV * u.y + (q.w * q.w - dotUU) * v.y +
              2.0f * q.w * cross.y,
          2.0f * dotUV * u.z + (q.w * q.w - dotUU) * v.z +
              2.0f * q.w * cross.z};
}

void anchorUI() {
  const auto& head = locatedViews[0].pose;
  const XrVector3f center{
      (locatedViews[0].pose.position.x + locatedViews[1].pose.position.x) *
          0.5f,
      (locatedViews[0].pose.position.y + locatedViews[1].pose.position.y) *
          0.5f,
      (locatedViews[0].pose.position.z + locatedViews[1].pose.position.z) *
          0.5f};
  XrVector3f forward = rotateVector(head.orientation, {0, 0, -1});
  // A world-anchored menu should remain upright and at eye height even if
  // F8 is pressed while the player is looking down. Keep only head yaw.
  forward.y = 0.0f;
  const float horizontalLength =
      std::sqrt(forward.x * forward.x + forward.z * forward.z);
  if (horizontalLength > 0.0001f) {
    forward.x /= horizontalLength;
    forward.z /= horizontalLength;
  } else {
    forward = {0, 0, -1};
  }
  const float yaw = std::atan2(-forward.x, -forward.z);
  uiPose.orientation = {0, std::sin(yaw * 0.5f), 0,
                        std::cos(yaw * 0.5f)};
  uiPose.position = {
      center.x + forward.x * 1.45f,
      center.y - 0.03f,
      center.z + forward.z * 1.45f};
  uiAnchorValid = true;
}

void anchorBattle() {
  const auto& head = locatedViews[0].pose;
  const XrVector3f center{
      (locatedViews[0].pose.position.x + locatedViews[1].pose.position.x) *
          0.5f,
      (locatedViews[0].pose.position.y + locatedViews[1].pose.position.y) *
          0.5f,
      (locatedViews[0].pose.position.z + locatedViews[1].pose.position.z) *
          0.5f};
  XrVector3f forward = rotateVector(head.orientation, {0, 0, -1});
  forward.y = 0.0f;
  const float length =
      std::sqrt(forward.x * forward.x + forward.z * forward.z);
  if (length > 0.0001f) {
    forward.x /= length;
    forward.z /= length;
  } else {
    forward = {0, 0, -1};
  }
  const float yaw = std::atan2(-forward.x, -forward.z);
  const XrQuaternionf orientation{0, std::sin(yaw * 0.5f), 0,
                                  std::cos(yaw * 0.5f)};
  const auto place = [&](XrPosef& pose, float distance) {
    pose.orientation = orientation;
    pose.position = {
        center.x + forward.x * distance,
        center.y + distance * 0.07f,
        center.z + forward.z * distance};
  };
  place(battlePose, 1.85f);
  place(enemyPose, 1.65f);
  place(attackPose, 1.47f);
  place(playerPose, 1.30f);
  place(hudPose, 1.18f);
  battleAnchorValid = true;
}

bool captureCanvas(Swapchain& target, uint32_t sourceWidth,
                   uint32_t sourceHeight, bool flipY, const char* label) {
  if (!frameBegun || !target.acquired || sourceWidth < 1 ||
      sourceHeight < 1) {
    lastError = std::string("OpenXR ") + label +
                " capture was requested outside an active frame";
    return false;
  }
  if (!loadGL()) return false;
  GLint previousRead = 0;
  GLint previousDraw = 0;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING_VALUE, &previousRead);
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING_VALUE, &previousDraw);
  GLuint fbo = 0;
  gl.genFramebuffers(1, &fbo);
  gl.bindFramebuffer(GL_READ_FRAMEBUFFER_VALUE,
                     static_cast<GLuint>(previousRead));
  gl.bindFramebuffer(GL_DRAW_FRAMEBUFFER_VALUE, fbo);
  gl.framebufferTexture2D(
      GL_DRAW_FRAMEBUFFER_VALUE, GL_COLOR_ATTACHMENT0_VALUE, GL_TEXTURE_2D,
      target.images[target.acquiredIndex].image, 0);
  if (gl.checkFramebufferStatus(GL_DRAW_FRAMEBUFFER_VALUE) !=
      GL_FRAMEBUFFER_COMPLETE_VALUE) {
    lastError = std::string("OpenXR ") + label +
                " swapchain framebuffer is incomplete";
    gl.bindFramebuffer(GL_READ_FRAMEBUFFER_VALUE,
                       static_cast<GLuint>(previousRead));
    gl.bindFramebuffer(GL_DRAW_FRAMEBUFFER_VALUE,
                       static_cast<GLuint>(previousDraw));
    gl.deleteFramebuffers(1, &fbo);
    return false;
  }
  const GLint sourceY0 = flipY ? static_cast<GLint>(sourceHeight) : 0;
  const GLint sourceY1 = flipY ? 0 : static_cast<GLint>(sourceHeight);
  gl.blitFramebuffer(0, sourceY0, static_cast<GLint>(sourceWidth),
                     sourceY1, 0, 0,
                     target.width, target.height,
                     GL_COLOR_BUFFER_BIT, GL_NEAREST);
  gl.bindFramebuffer(GL_READ_FRAMEBUFFER_VALUE,
                     static_cast<GLuint>(previousRead));
  gl.bindFramebuffer(GL_DRAW_FRAMEBUFFER_VALUE,
                     static_cast<GLuint>(previousDraw));
  gl.deleteFramebuffers(1, &fbo);
  return true;
}

bool endEmptyFrame() {
  if (!frameBegun) return true;
  releaseAcquired();
  XrFrameEndInfo end{XR_TYPE_FRAME_END_INFO};
  end.displayTime = frameState.predictedDisplayTime;
  end.environmentBlendMode = XR_ENVIRONMENT_BLEND_MODE_OPAQUE;
  end.layerCount = 0;
  end.layers = nullptr;
  const bool ok = xrOK("xrEndFrame", xrEndFrame(session, &end));
  frameBegun = false;
  return ok;
}

}  // namespace

extern "C" {

struct Gen1VRView {
  float position[3];
  float orientation[4];
  float fov[4];
};

struct Gen1VRController {
  uint32_t active;
  float position[3];
  float orientation[4];
  uint32_t profile;
};

struct Gen1VRFrame {
  uint32_t view_count;
  uint32_t recommended_width;
  uint32_t recommended_height;
  Gen1VRView views[2];
  Gen1VRController controllers[2];
};

GEN1_EXPORT void gen1openxr_shutdown();

GEN1_EXPORT int gen1openxr_init() {
  if (instance != XR_NULL_HANDLE && session != XR_NULL_HANDLE) return 1;
  // A previous attempt may have failed after xrCreateInstance but before a
  // usable session existed.  Never report that partial state as initialized:
  // Quest would then wait forever because begin_frame cannot submit anything.
  if (instance != XR_NULL_HANDLE || session != XR_NULL_HANDLE) {
    gen1openxr_shutdown();
  }
  lastError.clear();
#ifdef __ANDROID__
  using GetJNIEnvFn = void* (*)();
  using GetActivityFn = jobject (*)();
  auto getJNIEnv = reinterpret_cast<GetJNIEnvFn>(
      loveSymbol("SDL_AndroidGetJNIEnv"));
  auto getActivity = reinterpret_cast<GetActivityFn>(
      loveSymbol("SDL_AndroidGetActivity"));
  JNIEnv* env = getJNIEnv ? static_cast<JNIEnv*>(getJNIEnv()) : nullptr;
  jobject localActivity = getActivity ? getActivity() : nullptr;
  JavaVM* vm = nullptr;
  if (!env || !localActivity || env->GetJavaVM(&vm) != JNI_OK || !vm) {
    lastError = "LÖVE Android activity is unavailable to OpenXR";
    return 0;
  }
  // SDL returns a JNI local reference. The Android OpenXR loader retains the
  // context and still uses it after xrInitializeLoaderKHR returns, so promote
  // it to a process-lifetime global reference before handing it to the loader.
  // Keeping one reference alive also makes delayed initialization retries safe.
  if (!androidActivity) {
    androidActivity = env->NewGlobalRef(localActivity);
  }
  env->DeleteLocalRef(localActivity);
  if (!androidActivity) {
    lastError = "could not retain the Android activity for OpenXR";
    return 0;
  }
  PFN_xrInitializeLoaderKHR initializeLoader = nullptr;
  if (XR_FAILED(xrGetInstanceProcAddr(
          XR_NULL_HANDLE, "xrInitializeLoaderKHR",
          reinterpret_cast<PFN_xrVoidFunction*>(&initializeLoader))) ||
      !initializeLoader) {
    lastError = "Android OpenXR loader initialization is unavailable";
    return 0;
  }
  XrLoaderInitInfoAndroidKHR loaderInfo{
      XR_TYPE_LOADER_INIT_INFO_ANDROID_KHR};
  loaderInfo.applicationVM = vm;
  loaderInfo.applicationContext = androidActivity;
  if (!xrOK("xrInitializeLoaderKHR",
            initializeLoader(
                reinterpret_cast<const XrLoaderInitInfoBaseHeaderKHR*>(
                    &loaderInfo)))) {
    return 0;
  }
  const char* graphicsExtension =
      XR_KHR_OPENGL_ES_ENABLE_EXTENSION_NAME;
#else
  const char* graphicsExtension = XR_KHR_OPENGL_ENABLE_EXTENSION_NAME;
#endif
  std::vector<const char*> extensions{graphicsExtension};

  // Fail with a useful message before xrCreateInstance.  This distinguishes
  // an inactive/missing runtime from a runtime that cannot accept OpenGL.
  uint32_t extensionCount = 0;
  if (!xrOK("xrEnumerateInstanceExtensionProperties",
            xrEnumerateInstanceExtensionProperties(
                nullptr, 0, &extensionCount, nullptr))) {
    return 0;
  }
  std::vector<XrExtensionProperties> availableExtensions(extensionCount);
  for (auto& property : availableExtensions) {
    property = {XR_TYPE_EXTENSION_PROPERTIES};
  }
  if (!xrOK("xrEnumerateInstanceExtensionProperties",
            xrEnumerateInstanceExtensionProperties(
                nullptr, extensionCount, &extensionCount,
                availableExtensions.data()))) {
    return 0;
  }
  bool hasOpenGL = false;
  bool hasTouchPlus = false;
  bool hasRefreshRateExtension = false;
  for (const auto& property : availableExtensions) {
    if (std::strcmp(property.extensionName, graphicsExtension) == 0) {
      hasOpenGL = true;
    }
    if (std::strcmp(property.extensionName,
                    XR_META_TOUCH_CONTROLLER_PLUS_EXTENSION_NAME) == 0) {
      hasTouchPlus = true;
    }
    if (std::strcmp(property.extensionName,
                    XR_FB_DISPLAY_REFRESH_RATE_EXTENSION_NAME) == 0) {
      hasRefreshRateExtension = true;
    }
  }
  if (!hasOpenGL) {
    lastError = "active OpenXR runtime does not support the required GL API";
    return 0;
  }

  XrInstanceCreateInfo create{XR_TYPE_INSTANCE_CREATE_INFO};
  std::strncpy(create.applicationInfo.applicationName, "gen1recomp VR",
               XR_MAX_APPLICATION_NAME_SIZE - 1);
  create.applicationInfo.applicationVersion = 1;
  std::strncpy(create.applicationInfo.engineName, "LOVE",
               XR_MAX_ENGINE_NAME_SIZE - 1);
  create.applicationInfo.engineVersion = 115;
  // SteamVR builds that expose OpenXR 1.0 reject an application requesting
  // the 1.1 version from newer vcpkg headers.  This bridge only uses 1.0
  // core entry points, so request the compatible baseline deliberately.
  create.applicationInfo.apiVersion = XR_MAKE_VERSION(1, 0, 0);
  if (hasTouchPlus) {
    extensions.push_back(XR_META_TOUCH_CONTROLLER_PLUS_EXTENSION_NAME);
  }
  if (hasRefreshRateExtension) {
    extensions.push_back(XR_FB_DISPLAY_REFRESH_RATE_EXTENSION_NAME);
  }
  create.enabledExtensionCount = static_cast<uint32_t>(extensions.size());
  create.enabledExtensionNames = extensions.data();
  if (!xrOK("xrCreateInstance", xrCreateInstance(&create, &instance))) return 0;

  hasDisplayRefreshRate = hasRefreshRateExtension;
  if (hasDisplayRefreshRate) {
    xrGetInstanceProcAddr(instance, "xrEnumerateDisplayRefreshRatesFB",
      reinterpret_cast<PFN_xrVoidFunction*>(&enumerateDisplayRefreshRates));
    xrGetInstanceProcAddr(instance, "xrGetDisplayRefreshRateFB",
      reinterpret_cast<PFN_xrVoidFunction*>(&getDisplayRefreshRate));
    xrGetInstanceProcAddr(instance, "xrRequestDisplayRefreshRateFB",
      reinterpret_cast<PFN_xrVoidFunction*>(&requestDisplayRefreshRate));
    hasDisplayRefreshRate = enumerateDisplayRefreshRates
      && requestDisplayRefreshRate;
  }

  if (!createInputActions()) return 0;

  XrSystemGetInfo systemInfo{XR_TYPE_SYSTEM_GET_INFO};
  systemInfo.formFactor = XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY;
  if (!xrOK("xrGetSystem",
            xrGetSystem(instance, &systemInfo, &systemId))) {
    return 0;
  }

#ifdef __ANDROID__
  PFN_xrGetOpenGLESGraphicsRequirementsKHR getRequirements = nullptr;
  const char* requirementsName = "xrGetOpenGLESGraphicsRequirementsKHR";
#else
  PFN_xrGetOpenGLGraphicsRequirementsKHR getRequirements = nullptr;
  const char* requirementsName = "xrGetOpenGLGraphicsRequirementsKHR";
#endif
  if (!xrOK("xrGetInstanceProcAddr",
            xrGetInstanceProcAddr(
                instance, requirementsName,
                reinterpret_cast<PFN_xrVoidFunction*>(&getRequirements)))) {
    return 0;
  }
#ifdef __ANDROID__
  XrGraphicsRequirementsOpenGLESKHR requirements{
      XR_TYPE_GRAPHICS_REQUIREMENTS_OPENGL_ES_KHR};
  if (!xrOK("xrGetOpenGLESGraphicsRequirementsKHR",
            getRequirements(instance, systemId, &requirements))) {
    return 0;
  }
  const EGLDisplay display = eglGetCurrentDisplay();
  const EGLContext context = eglGetCurrentContext();
  EGLint configId = 0;
  EGLConfig config = nullptr;
  EGLint configCount = 0;
  if (display == EGL_NO_DISPLAY || context == EGL_NO_CONTEXT ||
      !eglQueryContext(display, context, EGL_CONFIG_ID, &configId)) {
    lastError = "LÖVE has no current Android OpenGL ES context";
    return 0;
  }
  const EGLint configAttributes[] = {EGL_CONFIG_ID, configId, EGL_NONE};
  if (!eglChooseConfig(display, configAttributes, &config, 1,
                       &configCount) || configCount < 1) {
    lastError = "could not resolve LÖVE's Android EGL configuration";
    return 0;
  }
  XrGraphicsBindingOpenGLESAndroidKHR binding{
      XR_TYPE_GRAPHICS_BINDING_OPENGL_ES_ANDROID_KHR};
  binding.display = display;
  binding.config = config;
  binding.context = context;
#else
  XrGraphicsRequirementsOpenGLKHR requirements{
      XR_TYPE_GRAPHICS_REQUIREMENTS_OPENGL_KHR};
  if (!xrOK("xrGetOpenGLGraphicsRequirementsKHR",
            getRequirements(instance, systemId, &requirements))) {
    return 0;
  }

  const HDC dc = wglGetCurrentDC();
  const HGLRC context = wglGetCurrentContext();
  if (!dc || !context) {
    lastError = "LÖVE has no current Win32 OpenGL context";
    return 0;
  }
  XrGraphicsBindingOpenGLWin32KHR binding{
      XR_TYPE_GRAPHICS_BINDING_OPENGL_WIN32_KHR};
  binding.hDC = dc;
  binding.hGLRC = context;
#endif
  XrSessionCreateInfo sessionInfo{XR_TYPE_SESSION_CREATE_INFO};
  sessionInfo.next = &binding;
  sessionInfo.systemId = systemId;
  if (!xrOK("xrCreateSession",
            xrCreateSession(instance, &sessionInfo, &session))) {
    return 0;
  }

  XrActionSpaceCreateInfo pointerSpaceInfo{XR_TYPE_ACTION_SPACE_CREATE_INFO};
  pointerSpaceInfo.action = pointerPoseAction;
  pointerSpaceInfo.poseInActionSpace.orientation.w = 1.0f;
  if (!xrOK("xrCreateActionSpace",
            xrCreateActionSpace(session, &pointerSpaceInfo,
                                &pointerAimSpace))) {
    return 0;
  }
  for (size_t hand = 0; hand < gripSpaces.size(); ++hand) {
    XrActionSpaceCreateInfo gripSpaceInfo{XR_TYPE_ACTION_SPACE_CREATE_INFO};
    gripSpaceInfo.action = gripPoseAction;
    gripSpaceInfo.subactionPath = handPaths[hand];
    gripSpaceInfo.poseInActionSpace.orientation.w = 1.0f;
    if (!xrOK("xrCreateActionSpace(controller grip)",
              xrCreateActionSpace(session, &gripSpaceInfo,
                                  &gripSpaces[hand]))) {
      return 0;
    }
  }

  XrSessionActionSetsAttachInfo attach{XR_TYPE_SESSION_ACTION_SETS_ATTACH_INFO};
  attach.countActionSets = 1;
  attach.actionSets = &inputActionSet;
  if (!xrOK("xrAttachSessionActionSets",
            xrAttachSessionActionSets(session, &attach))) {
    return 0;
  }

  XrReferenceSpaceCreateInfo spaceInfo{XR_TYPE_REFERENCE_SPACE_CREATE_INFO};
  spaceInfo.referenceSpaceType = XR_REFERENCE_SPACE_TYPE_LOCAL;
  spaceInfo.poseInReferenceSpace.orientation.w = 1.0f;
  if (!xrOK("xrCreateReferenceSpace",
            xrCreateReferenceSpace(session, &spaceInfo, &localSpace))) {
    return 0;
  }

  uint32_t viewCount = 0;
  if (!xrOK("xrEnumerateViewConfigurationViews",
            xrEnumerateViewConfigurationViews(
                instance, systemId, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO,
                0, &viewCount, nullptr))) {
    return 0;
  }
  if (viewCount < 2) {
    lastError = "OpenXR runtime did not expose two stereo views";
    return 0;
  }
  viewCount = 2;
  if (!xrOK("xrEnumerateViewConfigurationViews",
            xrEnumerateViewConfigurationViews(
                instance, systemId, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO,
                viewCount, &viewCount, configViews.data()))) {
    return 0;
  }
  return createSwapchains() ? 1 : 0;
}

GEN1_EXPORT int gen1openxr_set_refresh_rate(float rate) {
  if (rate > 0.0f) preferredDisplayRefreshRate = rate;
  if (!hasDisplayRefreshRate) return 0;
  // Before READY, retain the request; pollEvents applies it immediately
  // after xrBeginSession. While focused, apply it live from VR OPTION.
  if (!sessionRunning) return 1;
  return applyPreferredDisplayRefreshRate() ? 1 : 0;
}

GEN1_EXPORT float gen1openxr_get_refresh_rate() {
  if (getDisplayRefreshRate && session != XR_NULL_HANDLE) {
    float current = 0.0f;
    if (XR_SUCCEEDED(getDisplayRefreshRate(session, &current)) && current > 0) {
      activeDisplayRefreshRate = current;
    }
  }
  return activeDisplayRefreshRate;
}

GEN1_EXPORT int gen1openxr_begin_frame(Gen1VRFrame* out) {
  if (!out || instance == XR_NULL_HANDLE || session == XR_NULL_HANDLE) return 0;
  if (!pollEvents() || !sessionRunning) return 0;

  // Keep driving the OpenXR frame loop immediately after xrBeginSession.
  // On Quest the runtime may not deliver SYNCHRONIZED/VISIBLE/FOCUSED until
  // the application has entered xrWaitFrame at least once. Gating xrWaitFrame
  // on FOCUSED therefore deadlocks the launch in READY forever. We still end
  // an empty frame outside FOCUSED so no game rendering or swapchain work is
  // performed while the shell owns immersive focus.
  XrFrameWaitInfo wait{XR_TYPE_FRAME_WAIT_INFO};
  frameState = {XR_TYPE_FRAME_STATE};
  if (!xrOK("xrWaitFrame", xrWaitFrame(session, &wait, &frameState))) return 0;
  XrFrameBeginInfo begin{XR_TYPE_FRAME_BEGIN_INFO};
  if (!xrOK("xrBeginFrame", xrBeginFrame(session, &begin))) return 0;
  frameBegun = true;
  if (sessionState != XR_SESSION_STATE_FOCUSED ||
      !frameState.shouldRender) {
    endEmptyFrame();
    return 0;
  }

  XrViewLocateInfo locate{XR_TYPE_VIEW_LOCATE_INFO};
  locate.viewConfigurationType = XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
  locate.displayTime = frameState.predictedDisplayTime;
  locate.space = localSpace;
  XrViewState viewState{XR_TYPE_VIEW_STATE};
  uint32_t count = 0;
  locatedViews[0] = {XR_TYPE_VIEW};
  locatedViews[1] = {XR_TYPE_VIEW};
  if (!xrOK("xrLocateViews",
            xrLocateViews(session, &locate, &viewState, 2, &count,
                          locatedViews.data()))) {
    endEmptyFrame();
    return 0;
  }
  const XrViewStateFlags valid =
      XR_VIEW_STATE_POSITION_VALID_BIT | XR_VIEW_STATE_ORIENTATION_VALID_BIT;
  if (count < 2 || (viewState.viewStateFlags & valid) != valid) {
    lastError = "OpenXR headset pose is not valid";
    endEmptyFrame();
    return 0;
  }
  updatePointerHit();
  updateGripPoses();
  if (!acquireSwapchains()) {
    endEmptyFrame();
    return 0;
  }

  out->view_count = 2;
  out->recommended_width = configViews[0].recommendedImageRectWidth;
  out->recommended_height = configViews[0].recommendedImageRectHeight;
  for (uint32_t eye = 0; eye < 2; ++eye) {
    const auto& view = locatedViews[eye];
    auto& dest = out->views[eye];
    dest.position[0] = view.pose.position.x;
    dest.position[1] = view.pose.position.y;
    dest.position[2] = view.pose.position.z;
    dest.orientation[0] = view.pose.orientation.x;
    dest.orientation[1] = view.pose.orientation.y;
    dest.orientation[2] = view.pose.orientation.z;
    dest.orientation[3] = view.pose.orientation.w;
    dest.fov[0] = view.fov.angleLeft;
    dest.fov[1] = view.fov.angleRight;
    dest.fov[2] = view.fov.angleUp;
    dest.fov[3] = view.fov.angleDown;
  }
  for (size_t hand = 0; hand < 2; ++hand) {
    auto& dest = out->controllers[hand];
    dest.active = gripActive[hand] ? 1u : 0u;
    dest.position[0] = gripPoses[hand].position.x;
    dest.position[1] = gripPoses[hand].position.y;
    dest.position[2] = gripPoses[hand].position.z;
    dest.orientation[0] = gripPoses[hand].orientation.x;
    dest.orientation[1] = gripPoses[hand].orientation.y;
    dest.orientation[2] = gripPoses[hand].orientation.z;
    dest.orientation[3] = gripPoses[hand].orientation.w;
    dest.profile = controllerProfile(hand);
  }
  return 1;
}

GEN1_EXPORT int gen1openxr_capture_ui(
    uint32_t sourceWidth, uint32_t sourceHeight, int flipY) {
  if (!frameBegun || !uiSwapchain.acquired || sourceWidth < 1 ||
      sourceHeight < 1) {
    lastError = "OpenXR UI capture was requested outside an active frame";
    return 0;
  }
  if (!loadGL()) return 0;

  GLint previousRead = 0;
  GLint previousDraw = 0;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING_VALUE, &previousRead);
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING_VALUE, &previousDraw);
  GLuint fbo = 0;
  gl.genFramebuffers(1, &fbo);
  gl.bindFramebuffer(GL_READ_FRAMEBUFFER_VALUE,
                     static_cast<GLuint>(previousRead));
  gl.bindFramebuffer(GL_DRAW_FRAMEBUFFER_VALUE, fbo);
  gl.framebufferTexture2D(
      GL_DRAW_FRAMEBUFFER_VALUE, GL_COLOR_ATTACHMENT0_VALUE, GL_TEXTURE_2D,
      uiSwapchain.images[uiSwapchain.acquiredIndex].image, 0);
  if (gl.checkFramebufferStatus(GL_DRAW_FRAMEBUFFER_VALUE) !=
      GL_FRAMEBUFFER_COMPLETE_VALUE) {
    lastError = "OpenXR UI swapchain framebuffer is incomplete";
    gl.bindFramebuffer(GL_READ_FRAMEBUFFER_VALUE,
                       static_cast<GLuint>(previousRead));
    gl.bindFramebuffer(GL_DRAW_FRAMEBUFFER_VALUE,
                       static_cast<GLuint>(previousDraw));
    gl.deleteFramebuffers(1, &fbo);
    return 0;
  }
  // LÖVE's offscreen Canvas uses the opposite framebuffer orientation from
  // the Android window. Game UI is captured from a Canvas; the launcher is
  // captured from the window, so the caller tells us which path is active.
  const GLint sourceY0 = flipY ? static_cast<GLint>(sourceHeight) : 0;
  const GLint sourceY1 = flipY ? 0 : static_cast<GLint>(sourceHeight);
  gl.blitFramebuffer(0, sourceY0, static_cast<GLint>(sourceWidth),
                     sourceY1, 0, 0,
                     uiSwapchain.width, uiSwapchain.height,
                     GL_COLOR_BUFFER_BIT, GL_NEAREST);
  gl.bindFramebuffer(GL_READ_FRAMEBUFFER_VALUE,
                     static_cast<GLuint>(previousRead));
  gl.bindFramebuffer(GL_DRAW_FRAMEBUFFER_VALUE,
                     static_cast<GLuint>(previousDraw));
  gl.deleteFramebuffers(1, &fbo);

  if (!uiAnchorValid) anchorUI();
  uiCaptured = true;
  return 1;
}

GEN1_EXPORT int gen1openxr_capture_battle(
    uint32_t sourceWidth, uint32_t sourceHeight, int flipY) {
  if (!frameBegun || !battleSwapchain.acquired || sourceWidth < 1 ||
      sourceHeight < 1) {
    lastError = "OpenXR battle capture was requested outside an active frame";
    return 0;
  }
  if (!loadGL()) return 0;

  GLint previousRead = 0;
  GLint previousDraw = 0;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING_VALUE, &previousRead);
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING_VALUE, &previousDraw);
  GLuint fbo = 0;
  gl.genFramebuffers(1, &fbo);
  gl.bindFramebuffer(GL_READ_FRAMEBUFFER_VALUE,
                     static_cast<GLuint>(previousRead));
  gl.bindFramebuffer(GL_DRAW_FRAMEBUFFER_VALUE, fbo);
  gl.framebufferTexture2D(
      GL_DRAW_FRAMEBUFFER_VALUE, GL_COLOR_ATTACHMENT0_VALUE, GL_TEXTURE_2D,
      battleSwapchain.images[battleSwapchain.acquiredIndex].image, 0);
  if (gl.checkFramebufferStatus(GL_DRAW_FRAMEBUFFER_VALUE) !=
      GL_FRAMEBUFFER_COMPLETE_VALUE) {
    lastError = "OpenXR battle swapchain framebuffer is incomplete";
    gl.bindFramebuffer(GL_READ_FRAMEBUFFER_VALUE,
                       static_cast<GLuint>(previousRead));
    gl.bindFramebuffer(GL_DRAW_FRAMEBUFFER_VALUE,
                       static_cast<GLuint>(previousDraw));
    gl.deleteFramebuffers(1, &fbo);
    return 0;
  }
  const GLint sourceY0 = flipY ? static_cast<GLint>(sourceHeight) : 0;
  const GLint sourceY1 = flipY ? 0 : static_cast<GLint>(sourceHeight);
  gl.blitFramebuffer(0, sourceY0, static_cast<GLint>(sourceWidth),
                     sourceY1, 0, 0,
                     battleSwapchain.width, battleSwapchain.height,
                     GL_COLOR_BUFFER_BIT, GL_NEAREST);
  gl.bindFramebuffer(GL_READ_FRAMEBUFFER_VALUE,
                     static_cast<GLuint>(previousRead));
  gl.bindFramebuffer(GL_DRAW_FRAMEBUFFER_VALUE,
                     static_cast<GLuint>(previousDraw));
  gl.deleteFramebuffers(1, &fbo);

  if (!battleWasVisible) {
    // A new battle gets a fresh shared anchor. The command panel and stage
    // are then stable LOCAL-space objects, rather than head-locked images.
    uiAnchorValid = false;
    battleAnchorValid = false;
  }
  if (!battleAnchorValid) anchorBattle();
  battleCaptured = true;
  return 1;
}

GEN1_EXPORT int gen1openxr_capture_battle_enemy(
    uint32_t sourceWidth, uint32_t sourceHeight, int flipY) {
  if (!captureCanvas(enemySwapchain, sourceWidth, sourceHeight,
                     flipY != 0, "enemy layer")) return 0;
  if (!battleAnchorValid) anchorBattle();
  enemyCaptured = true;
  return 1;
}

GEN1_EXPORT int gen1openxr_capture_battle_attack(
    uint32_t sourceWidth, uint32_t sourceHeight, int flipY) {
  if (!captureCanvas(attackSwapchain, sourceWidth, sourceHeight,
                     flipY != 0, "attack layer")) return 0;
  if (!battleAnchorValid) anchorBattle();
  attackCaptured = true;
  return 1;
}

GEN1_EXPORT int gen1openxr_capture_battle_player(
    uint32_t sourceWidth, uint32_t sourceHeight, int flipY) {
  if (!captureCanvas(playerSwapchain, sourceWidth, sourceHeight,
                     flipY != 0, "player layer")) return 0;
  if (!battleAnchorValid) anchorBattle();
  playerCaptured = true;
  return 1;
}

GEN1_EXPORT int gen1openxr_capture_battle_hud(
    uint32_t sourceWidth, uint32_t sourceHeight, int flipY) {
  if (!captureCanvas(hudSwapchain, sourceWidth, sourceHeight,
                     flipY != 0, "battle HUD layer")) return 0;
  if (!battleAnchorValid) anchorBattle();
  hudCaptured = true;
  return 1;
}

struct Gen1VRInput {
  uint32_t buttons;
  float move_x;
  float move_y;
  float turn_x;
  float turn_y;
  uint32_t pointer_active;
  float pointer_x;
  float pointer_y;
  uint32_t pointer_down;
  Gen1VRController controllers[2];
};

GEN1_EXPORT int gen1openxr_poll_events() {
  if (instance == XR_NULL_HANDLE) return 0;
  if (!pollEvents()) return 0;
  // 1 means the lifecycle pump succeeded but the app must remain suspended.
  // 2 means OpenXR itself confirms that immersive focus has returned.  SDL
  // occasionally misses the matching focus/visibility callback after Quest
  // Games Optimizer or Horizon ClearActivity briefly covers the app, so Lua
  // uses this native state to recover instead of remaining paused forever.
  return sessionRunning && sessionState == XR_SESSION_STATE_FOCUSED ? 2 : 1;
}

GEN1_EXPORT int gen1openxr_poll_input(Gen1VRInput* out) {
  if (!out) return 0;
  *out = {};
  if (instance == XR_NULL_HANDLE || session == XR_NULL_HANDLE ||
      inputActionSet == XR_NULL_HANDLE) return 0;
  // begin_frame used to be the only event pump. When Android paused the SDL
  // surface, love.draw stopped but love.update could continue polling input;
  // sessionRunning therefore stayed stale and xrSyncActions hammered the
  // tracking broker without VR focus. Pump events here too and expose input
  // only in the FOCUSED state.
  if (!pollEvents() || !sessionRunning ||
      sessionState != XR_SESSION_STATE_FOCUSED) return 0;
  XrActiveActionSet active{inputActionSet, XR_NULL_PATH};
  XrActionsSyncInfo sync{XR_TYPE_ACTIONS_SYNC_INFO};
  sync.countActiveActionSets = 1;
  sync.activeActionSets = &active;
  if (!xrOK("xrSyncActions", xrSyncActions(session, &sync))) return 0;

  const XrVector2f move = actionVector(moveAction);
  const XrVector2f turn = actionVector(turnAction);
  uint32_t buttons = 0;
  if (move.y > 0.5f) buttons |= 0x01;
  if (move.y < -0.5f) buttons |= 0x02;
  if (move.x < -0.5f) buttons |= 0x04;
  if (move.x > 0.5f) buttons |= 0x08;
  const bool pointerDown = actionBoolean(pointerClickAction) ||
                           actionFloat(pointerTriggerAction) > 0.55f;
  const bool confirmDown = actionBoolean(aAction) || pointerDown;
  if (confirmDown) buttons |= 0x10;
  if (actionBoolean(bAction) || actionFloat(squeezeAction) > 0.65f)
    buttons |= 0x20;
  if (actionBoolean(startAction)) buttons |= 0x40;
  if (actionBoolean(selectAction)) buttons |= 0x80;
  if (actionBoolean(recenterAction)) buttons |= 0x100;
  out->buttons = buttons;
  out->move_x = move.x;
  out->move_y = move.y;
  out->turn_x = turn.x;
  out->turn_y = turn.y;
  out->pointer_active = pointerHitActive ? 1u : 0u;
  out->pointer_x = pointerHitX;
  out->pointer_y = pointerHitY;
  out->pointer_down = confirmDown ? 1u : 0u;
  for (size_t hand = 0; hand < 2; ++hand) {
    auto& dest = out->controllers[hand];
    dest.active = gripActive[hand] ? 1u : 0u;
    dest.position[0] = gripPoses[hand].position.x;
    dest.position[1] = gripPoses[hand].position.y;
    dest.position[2] = gripPoses[hand].position.z;
    dest.orientation[0] = gripPoses[hand].orientation.x;
    dest.orientation[1] = gripPoses[hand].orientation.y;
    dest.orientation[2] = gripPoses[hand].orientation.z;
    dest.orientation[3] = gripPoses[hand].orientation.w;
    dest.profile = controllerProfile(hand);
  }
  return 1;
}

GEN1_EXPORT void gen1openxr_recenter_ui() {
  // The next rendered UI frame captures a new fixed pose in front of the
  // current headset position. It remains there while the player looks away.
  uiAnchorValid = false;
  battleAnchorValid = false;
}

GEN1_EXPORT int gen1openxr_submit_frame(
    uint32_t framebufferWidth, uint32_t framebufferHeight,
    int projectionEnabled) {
  if (!frameBegun || framebufferWidth < 2 || framebufferHeight < 1) return 0;
  if (!loadGL()) {
    endEmptyFrame();
    return 0;
  }

  GLint previousRead = 0;
  GLint previousDraw = 0;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING_VALUE, &previousRead);
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING_VALUE, &previousDraw);
  GLuint fbo = 0;
  gl.genFramebuffers(1, &fbo);

  bool copied = true;
  if (projectionEnabled) {
    const GLint half = static_cast<GLint>(framebufferWidth / 2);
    for (uint32_t eye = 0; eye < 2; ++eye) {
      auto& sc = swapchains[eye];
      const GLuint texture = sc.images[sc.acquiredIndex].image;
      gl.bindFramebuffer(GL_READ_FRAMEBUFFER_VALUE,
                         static_cast<GLuint>(previousRead));
      gl.bindFramebuffer(GL_DRAW_FRAMEBUFFER_VALUE, fbo);
      gl.framebufferTexture2D(GL_DRAW_FRAMEBUFFER_VALUE,
                              GL_COLOR_ATTACHMENT0_VALUE, GL_TEXTURE_2D,
                              texture, 0);
      if (gl.checkFramebufferStatus(GL_DRAW_FRAMEBUFFER_VALUE) !=
          GL_FRAMEBUFFER_COMPLETE_VALUE) {
        lastError = "OpenXR swapchain framebuffer is incomplete";
        copied = false;
        break;
      }
      const GLint x0 = eye == 0 ? 0 : half;
      const GLint x1 = eye == 0 ? half : static_cast<GLint>(framebufferWidth);
      gl.blitFramebuffer(x0, 0, x1, static_cast<GLint>(framebufferHeight),
                         0, 0, sc.width, sc.height, GL_COLOR_BUFFER_BIT,
                         GL_LINEAR);
    }
  }
  gl.bindFramebuffer(GL_READ_FRAMEBUFFER_VALUE,
                     static_cast<GLuint>(previousRead));
  gl.bindFramebuffer(GL_DRAW_FRAMEBUFFER_VALUE,
                     static_cast<GLuint>(previousDraw));
  gl.deleteFramebuffers(1, &fbo);

  if (!copied) {
    endEmptyFrame();
    return 0;
  }
  releaseAcquired();

  std::array<XrCompositionLayerProjectionView, 2> projectionViews{{
      {XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW},
      {XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW},
  }};
  for (uint32_t eye = 0; eye < 2; ++eye) {
    auto& layerView = projectionViews[eye];
    layerView.pose = locatedViews[eye].pose;
    layerView.fov = locatedViews[eye].fov;
    layerView.subImage.swapchain = swapchains[eye].handle;
    layerView.subImage.imageRect.offset = {0, 0};
    layerView.subImage.imageRect.extent = {
        swapchains[eye].width, swapchains[eye].height};
    layerView.subImage.imageArrayIndex = 0;
  }
  XrCompositionLayerProjection layer{XR_TYPE_COMPOSITION_LAYER_PROJECTION};
  layer.space = localSpace;
  layer.viewCount = 2;
  layer.views = projectionViews.data();
  XrCompositionLayerQuad uiLayer{XR_TYPE_COMPOSITION_LAYER_QUAD};
  uiLayer.layerFlags = XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT;
  uiLayer.space = localSpace;
  uiLayer.eyeVisibility = XR_EYE_VISIBILITY_BOTH;
  uiLayer.subImage.swapchain = uiSwapchain.handle;
  uiLayer.subImage.imageRect.offset = {0, 0};
  uiLayer.subImage.imageRect.extent = {
      uiSwapchain.width, uiSwapchain.height};
  uiLayer.subImage.imageArrayIndex = 0;
  uiLayer.pose = uiPose;
  uiLayer.size = {1.15f, 1.035f};

  XrCompositionLayerQuad battleLayer{XR_TYPE_COMPOSITION_LAYER_QUAD};
  battleLayer.layerFlags = XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT;
  battleLayer.space = localSpace;
  battleLayer.eyeVisibility = XR_EYE_VISIBILITY_BOTH;
  battleLayer.subImage.swapchain = battleSwapchain.handle;
  battleLayer.subImage.imageRect.offset = {0, 0};
  battleLayer.subImage.imageRect.extent = {
      battleSwapchain.width, battleSwapchain.height};
  battleLayer.subImage.imageArrayIndex = 0;
  battleLayer.pose = battlePose;
  battleLayer.size = {1.65f, 0.99f};

  const auto makeSpatialLayer = [](Swapchain& swapchain,
                                   const XrPosef& pose, float scale) {
    XrCompositionLayerQuad quad{XR_TYPE_COMPOSITION_LAYER_QUAD};
    quad.layerFlags = XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT;
    quad.space = localSpace;
    quad.eyeVisibility = XR_EYE_VISIBILITY_BOTH;
    quad.subImage.swapchain = swapchain.handle;
    quad.subImage.imageRect.offset = {0, 0};
    quad.subImage.imageRect.extent = {swapchain.width, swapchain.height};
    quad.subImage.imageArrayIndex = 0;
    quad.pose = pose;
    quad.size = {1.65f * scale, 0.99f * scale};
    return quad;
  };
  auto enemyLayer = makeSpatialLayer(enemySwapchain, enemyPose,
                                      1.65f / 1.85f);
  auto attackLayer = makeSpatialLayer(attackSwapchain, attackPose,
                                       1.47f / 1.85f);
  auto playerLayer = makeSpatialLayer(playerSwapchain, playerPose,
                                       1.30f / 1.85f);
  auto hudLayer = makeSpatialLayer(hudSwapchain, hudPose,
                                    1.18f / 1.85f);

  std::vector<const XrCompositionLayerBaseHeader*> layers;
  layers.reserve(7);
  if (projectionEnabled) {
    layers.push_back(
        reinterpret_cast<const XrCompositionLayerBaseHeader*>(&layer));
  }
  if (battleCaptured) layers.push_back(
      reinterpret_cast<const XrCompositionLayerBaseHeader*>(&battleLayer));
  if (enemyCaptured) layers.push_back(
      reinterpret_cast<const XrCompositionLayerBaseHeader*>(&enemyLayer));
  if (attackCaptured) layers.push_back(
      reinterpret_cast<const XrCompositionLayerBaseHeader*>(&attackLayer));
  if (playerCaptured) layers.push_back(
      reinterpret_cast<const XrCompositionLayerBaseHeader*>(&playerLayer));
  if (uiCaptured) layers.push_back(
      reinterpret_cast<const XrCompositionLayerBaseHeader*>(&uiLayer));
  if (hudCaptured) layers.push_back(
      reinterpret_cast<const XrCompositionLayerBaseHeader*>(&hudLayer));
  XrFrameEndInfo end{XR_TYPE_FRAME_END_INFO};
  end.displayTime = frameState.predictedDisplayTime;
  end.environmentBlendMode = XR_ENVIRONMENT_BLEND_MODE_OPAQUE;
  end.layerCount = static_cast<uint32_t>(layers.size());
  end.layers = layers.data();
  battleWasVisible = battleCaptured;
  if (!battleCaptured) battleAnchorValid = false;
  const bool ok = xrOK("xrEndFrame", xrEndFrame(session, &end));
  frameBegun = false;
  return ok ? 1 : 0;
}

GEN1_EXPORT void gen1openxr_cancel_frame() {
  endEmptyFrame();
}

GEN1_EXPORT void gen1openxr_shutdown() {
  if (frameBegun) endEmptyFrame();
  if (sessionRunning && session != XR_NULL_HANDLE) {
    // A running OpenXR session must first be asked to exit. Destroying a
    // FOCUSED session directly leaves some Quest runtimes holding the old app
    // session, so a later launch cannot start until the headset is rebooted.
    xrRequestExitSession(session);
    for (int i = 0; i < 60 && sessionRunning; ++i) {
      pollEvents();
      if (sessionRunning) std::this_thread::sleep_for(
          std::chrono::milliseconds(2));
    }
    // Last-resort cleanup for runtimes that did not deliver STOPPING in the
    // bounded window. Normally pollEvents already called xrEndSession.
    if (sessionRunning) xrEndSession(session);
  }
  sessionRunning = false;
  for (auto& sc : swapchains) {
    if (sc.handle != XR_NULL_HANDLE) xrDestroySwapchain(sc.handle);
    sc = {};
  }
  if (uiSwapchain.handle != XR_NULL_HANDLE) {
    xrDestroySwapchain(uiSwapchain.handle);
  }
  uiSwapchain = {};
  if (battleSwapchain.handle != XR_NULL_HANDLE) {
    xrDestroySwapchain(battleSwapchain.handle);
  }
  battleSwapchain = {};
  for (Swapchain* sc : {&enemySwapchain, &attackSwapchain,
                        &playerSwapchain, &hudSwapchain}) {
    if (sc->handle != XR_NULL_HANDLE) xrDestroySwapchain(sc->handle);
    *sc = {};
  }
  if (pointerAimSpace != XR_NULL_HANDLE) xrDestroySpace(pointerAimSpace);
  for (auto& space : gripSpaces) {
    if (space != XR_NULL_HANDLE) xrDestroySpace(space);
    space = XR_NULL_HANDLE;
  }
  if (localSpace != XR_NULL_HANDLE) xrDestroySpace(localSpace);
  if (session != XR_NULL_HANDLE) xrDestroySession(session);
  if (inputActionSet != XR_NULL_HANDLE) xrDestroyActionSet(inputActionSet);
  if (instance != XR_NULL_HANDLE) xrDestroyInstance(instance);
  localSpace = XR_NULL_HANDLE;
  pointerAimSpace = XR_NULL_HANDLE;
  session = XR_NULL_HANDLE;
  instance = XR_NULL_HANDLE;
  inputActionSet = XR_NULL_HANDLE;
  moveAction = turnAction = aAction = bAction = XR_NULL_HANDLE;
  startAction = selectAction = recenterAction = XR_NULL_HANDLE;
  pointerPoseAction = pointerClickAction = pointerTriggerAction = XR_NULL_HANDLE;
  squeezeAction = XR_NULL_HANDLE;
  gripPoseAction = XR_NULL_HANDLE;
  handPaths = {{XR_NULL_PATH, XR_NULL_PATH}};
  gripActive = {{false, false}};
  pointerHitActive = false;
  systemId = XR_NULL_SYSTEM_ID;
  sessionState = XR_SESSION_STATE_UNKNOWN;
  frameBegun = false;
  uiAnchorValid = false;
  uiCaptured = false;
  battleAnchorValid = false;
  battleCaptured = false;
  enemyCaptured = attackCaptured = playerCaptured = hudCaptured = false;
  battleWasVisible = false;
  hasDisplayRefreshRate = false;
  enumerateDisplayRefreshRates = nullptr;
  getDisplayRefreshRate = nullptr;
  requestDisplayRefreshRate = nullptr;
  activeDisplayRefreshRate = 0.0f;
}

GEN1_EXPORT const char* gen1openxr_last_error() {
  return lastError.c_str();
}

}  // extern "C"
