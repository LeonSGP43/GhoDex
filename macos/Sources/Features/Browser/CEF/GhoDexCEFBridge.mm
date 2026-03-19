#import "GhoDexCEFBridge.h"

NSString * const GhoDexCEFControlErrorDomain = @"com.leongong.ghodex.browser.cef.control";

@interface GhoDexCEFView (GhoDexCEFPrivateEvaluation)
- (void)failPendingEvaluationRequestsWithCode:(GhoDexCEFControlErrorCode)code
                                  description:(NSString *)description;
- (void)completeEvaluationRequestID:(NSString *)requestID
                         resultJSON:(NSString * _Nullable)resultJSON
                              error:(NSError * _Nullable)error;
- (void)notifyBridgeReady;
- (void)notifyConsoleMessage:(NSString *)message
                       level:(NSString *)level
                      source:(NSString *)source
                        line:(NSInteger)line;
@end

#if GHODEX_CEF_ENABLED

#include <algorithm>
#include <atomic>
#include <string>
#include <vector>

#include <dispatch/dispatch.h>

#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_parser.h"
#include "include/cef_render_process_handler.h"
#include "include/cef_v8.h"
#include "include/wrapper/cef_library_loader.h"
#include "include/wrapper/cef_helpers.h"

namespace {
std::atomic<int64_t> g_message_pump_generation{0};
std::atomic<bool> g_cef_initialized{false};
std::atomic<bool> g_cef_initializing{false};
std::atomic<bool> g_cef_library_loaded{false};
dispatch_source_t g_message_pump_timer = nullptr;
constexpr char kEvaluateRequestMessageName[] = "ghodex.browser.evaluate";
constexpr char kEvaluateResultMessageName[] = "ghodex.browser.evaluate.result";

constexpr size_t kEvaluateRequestIDIndex = 0;
constexpr size_t kEvaluateScriptIndex = 1;
constexpr size_t kEvaluateSuccessIndex = 1;
constexpr size_t kEvaluatePayloadIndex = 2;

NSError *MakeControlError(GhoDexCEFControlErrorCode code, NSString *description) {
  return [NSError errorWithDomain:GhoDexCEFControlErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey : description ?: @"Unknown browser control error."}];
}

NSString *ConsoleLevelString(cef_log_severity_t level) {
  switch (level) {
  case LOGSEVERITY_VERBOSE:
    return @"verbose";
  case LOGSEVERITY_INFO:
    return @"info";
  case LOGSEVERITY_WARNING:
    return @"warning";
  case LOGSEVERITY_ERROR:
    return @"error";
  case LOGSEVERITY_FATAL:
    return @"fatal";
  case LOGSEVERITY_DEFAULT:
  default:
    return @"info";
  }
}

id _Nullable FoundationObjectFromV8Value(CefRefPtr<CefV8Value> value,
                                         NSMutableSet<NSValue *> *visited_values,
                                         NSString **error_message,
                                         NSUInteger depth) {
  if (!value.get()) {
    return NSNull.null;
  }

  if (depth > 64) {
    if (error_message != nullptr) {
      *error_message = @"JavaScript evaluation exceeded the maximum serialization depth.";
    }
    return nil;
  }

  if (value->IsUndefined() || value->IsNull()) {
    return NSNull.null;
  }
  if (value->IsBool()) {
    return @(value->GetBoolValue());
  }
  if (value->IsInt()) {
    return @(value->GetIntValue());
  }
  if (value->IsUInt()) {
    return @((unsigned int)value->GetUIntValue());
  }
  if (value->IsDouble()) {
    return @(value->GetDoubleValue());
  }
  if (value->IsString()) {
    return [NSString stringWithUTF8String:value->GetStringValue().ToString().c_str() ?: ""];
  }
  if (value->IsArray()) {
    NSValue *identity = [NSValue valueWithPointer:value.get()];
    if ([visited_values containsObject:identity]) {
      if (error_message != nullptr) {
        *error_message = @"JavaScript evaluation returned a cyclic array value that cannot be serialized.";
      }
      return nil;
    }

    [visited_values addObject:identity];
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:(NSUInteger)value->GetArrayLength()];
    for (int index = 0; index < value->GetArrayLength(); index++) {
      NSString *nested_error = nil;
      id item = FoundationObjectFromV8Value(value->GetValue(index), visited_values, &nested_error, depth + 1);
      if (item == nil) {
        if (error_message != nullptr) {
          *error_message = nested_error ?: @"JavaScript evaluation returned an unsupported array element.";
        }
        [visited_values removeObject:identity];
        return nil;
      }
      [items addObject:item];
    }
    [visited_values removeObject:identity];
    return items;
  }
  if (value->IsObject()) {
    NSValue *identity = [NSValue valueWithPointer:value.get()];
    if ([visited_values containsObject:identity]) {
      if (error_message != nullptr) {
        *error_message = @"JavaScript evaluation returned a cyclic object value that cannot be serialized.";
      }
      return nil;
    }

    [visited_values addObject:identity];
    std::vector<CefString> keys;
    if (!value->GetKeys(keys)) {
      if (error_message != nullptr) {
        *error_message = @"JavaScript evaluation returned an object whose keys could not be enumerated.";
      }
      [visited_values removeObject:identity];
      return nil;
    }

    NSMutableDictionary<NSString *, id> *dictionary =
        [NSMutableDictionary dictionaryWithCapacity:keys.size()];
    for (const CefString &key : keys) {
      NSString *key_string = [NSString stringWithUTF8String:key.ToString().c_str() ?: ""];
      NSString *nested_error = nil;
      id nested_value =
          FoundationObjectFromV8Value(value->GetValue(key), visited_values, &nested_error, depth + 1);
      if (nested_value == nil) {
        if (error_message != nullptr) {
          *error_message = nested_error ?: @"JavaScript evaluation returned an unsupported object property.";
        }
        [visited_values removeObject:identity];
        return nil;
      }
      dictionary[key_string ?: @""] = nested_value;
    }

    [visited_values removeObject:identity];
    return dictionary;
  }

  if (error_message != nullptr) {
    *error_message = @"JavaScript evaluation returned a non-serializable value.";
  }
  return nil;
}

NSString *_Nullable JSONStringFromV8Value(CefRefPtr<CefV8Value> value, NSString **error_message) {
  NSMutableSet<NSValue *> *visited_values = [NSMutableSet set];
  id object = FoundationObjectFromV8Value(value, visited_values, error_message, 0);
  if (object == nil) {
    return nil;
  }

  NSError *json_error = nil;
  NSData *json_data = [NSJSONSerialization dataWithJSONObject:object
                                                      options:NSJSONWritingFragmentsAllowed
                                                        error:&json_error];
  if (json_data == nil) {
    if (error_message != nullptr) {
      *error_message = json_error.localizedDescription ?: @"JavaScript evaluation returned an unsupported JSON fragment.";
    }
    return nil;
  }

  return [[NSString alloc] initWithData:json_data encoding:NSUTF8StringEncoding];
}

void SendEvaluationResponse(CefRefPtr<CefFrame> frame,
                            const CefString &request_id,
                            bool success,
                            const CefString &payload) {
  if (!frame.get()) {
    return;
  }

  CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create(kEvaluateResultMessageName);
  CefRefPtr<CefListValue> arguments = message->GetArgumentList();
  arguments->SetString(kEvaluateRequestIDIndex, request_id);
  arguments->SetBool(kEvaluateSuccessIndex, success);
  arguments->SetString(kEvaluatePayloadIndex, payload);
  frame->SendProcessMessage(PID_BROWSER, message);
}

class GhoDexCEFEvaluationPromiseHandler final : public CefV8Handler {
public:
  GhoDexCEFEvaluationPromiseHandler(CefRefPtr<CefFrame> frame,
                                    const CefString &request_id,
                                    bool success)
      : frame_(frame), request_id_(request_id), success_(success) {}

  bool Execute(const CefString &name,
               CefRefPtr<CefV8Value> object,
               const CefV8ValueList &arguments,
               CefRefPtr<CefV8Value> &retval,
               CefString &exception) override {
    CEF_REQUIRE_RENDERER_THREAD();

    CefRefPtr<CefV8Value> payload_value = arguments.empty() ? nullptr : arguments.front();
    if (success_) {
      NSString *serialization_error = nil;
      NSString *result_json = JSONStringFromV8Value(payload_value, &serialization_error);
      if (result_json.length == 0 && serialization_error != nil) {
        SendEvaluationResponse(
            frame_,
            request_id_,
            false,
            std::string(serialization_error.UTF8String
                            ?: "The renderer could not serialize the JavaScript promise result."));
        return true;
      }

      SendEvaluationResponse(frame_, request_id_, true, std::string(result_json.UTF8String ?: "null"));
      return true;
    }

    std::string rejection_message = "JavaScript promise rejected.";
    if (payload_value.get()) {
      if (payload_value->IsString()) {
        rejection_message = payload_value->GetStringValue().ToString();
      } else if (payload_value->IsObject()) {
        CefRefPtr<CefV8Value> message_value = payload_value->GetValue("message");
        if (message_value.get() && message_value->IsString()) {
          rejection_message = message_value->GetStringValue().ToString();
        } else {
          NSString *serialization_error = nil;
          NSString *payload_json = JSONStringFromV8Value(payload_value, &serialization_error);
          if (payload_json.length > 0) {
            rejection_message = std::string(payload_json.UTF8String ?: "JavaScript promise rejected.");
          } else if (serialization_error != nil) {
            rejection_message = std::string(serialization_error.UTF8String ?: "JavaScript promise rejected.");
          }
        }
      }
    }

    SendEvaluationResponse(frame_, request_id_, false, rejection_message);
    return true;
  }

private:
  CefRefPtr<CefFrame> frame_;
  CefString request_id_;
  bool success_;

  IMPLEMENT_REFCOUNTING(GhoDexCEFEvaluationPromiseHandler);
};

class ScopedMainArgs {
public:
  ScopedMainArgs() {
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    storage_.reserve(arguments.count);
    argv_.reserve(arguments.count);

    for (NSString *argument in arguments) {
      storage_.emplace_back(argument.UTF8String ?: "");
    }

    for (auto &argument : storage_) {
      argv_.push_back(argument.data());
    }
  }

  CefMainArgs mainArgs() {
    return CefMainArgs(static_cast<int>(argv_.size()), argv_.data());
  }

private:
  std::vector<std::string> storage_;
  std::vector<char *> argv_;
};

void ScheduleMessagePumpWork(int64_t delay_ms) {
  if (!g_cef_initialized.load()) {
    return;
  }

  int64_t clamped_delay = std::max<int64_t>(0, delay_ms);
  uint64_t nanoseconds = static_cast<uint64_t>(clamped_delay) * NSEC_PER_MSEC;
  int64_t generation = ++g_message_pump_generation;

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(nanoseconds)), dispatch_get_main_queue(), ^{
    if (!g_cef_initialized.load()) {
      return;
    }
    if (generation != g_message_pump_generation.load()) {
      return;
    }

    CefDoMessageLoopWork();
  });
}

void StartMessagePumpTimer() {
  if (g_message_pump_timer != nullptr) {
    return;
  }

  dispatch_source_t timer =
      dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
  if (timer == nullptr) {
    return;
  }

  // Chromium child processes time out if the browser loop stops pumping for
  // too long, so keep a low-cost fallback timer active on the main queue.
  dispatch_source_set_timer(
      timer,
      dispatch_time(DISPATCH_TIME_NOW, 0),
      10 * NSEC_PER_MSEC,
      1 * NSEC_PER_MSEC);
  dispatch_source_set_event_handler(timer, ^{
    if (!g_cef_initialized.load()) {
      return;
    }

    CefDoMessageLoopWork();
  });
  dispatch_resume(timer);
  g_message_pump_timer = timer;
}

void StopMessagePumpTimer() {
  if (g_message_pump_timer == nullptr) {
    return;
  }

  dispatch_source_cancel(g_message_pump_timer);
  g_message_pump_timer = nullptr;
}

class GhoDexCEFApp final : public CefApp,
                           public CefBrowserProcessHandler,
                           public CefRenderProcessHandler {
public:
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
    return this;
  }
  CefRefPtr<CefRenderProcessHandler> GetRenderProcessHandler() override {
    return this;
  }

  void OnBeforeCommandLineProcessing(
      const CefString &process_type,
      CefRefPtr<CefCommandLine> command_line) override;
  bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser,
                                CefRefPtr<CefFrame> frame,
                                CefProcessId source_process,
                                CefRefPtr<CefProcessMessage> message) override;

  void OnScheduleMessagePumpWork(int64_t delay_ms) override {
    ScheduleMessagePumpWork(delay_ms);
  }

  IMPLEMENT_REFCOUNTING(GhoDexCEFApp);
};

class GhoDexCEFClient final : public CefClient,
                              public CefDisplayHandler,
                              public CefLifeSpanHandler,
                              public CefLoadHandler {
public:
  explicit GhoDexCEFClient(GhoDexCEFView *owner) : owner_(owner) {}

  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser,
                                CefRefPtr<CefFrame> frame,
                                CefProcessId source_process,
                                CefRefPtr<CefProcessMessage> message) override;

  void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &title) override;
  bool OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                        cef_log_severity_t level,
                        const CefString &message,
                        const CefString &source,
                        int line) override;

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    browser_ = browser;
    NSLog(@"[CEF] Browser created for %@", owner_);
    if (owner_) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [owner_ notifyBridgeReady];
      });
    }
    EmitState(browser->IsLoading(), browser->CanGoBack(), browser->CanGoForward());
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    if (browser_ && browser_->GetIdentifier() == browser->GetIdentifier()) {
      if (owner_) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [owner_ failPendingEvaluationRequestsWithCode:GhoDexCEFControlErrorCodeBridgeUnavailable
                                            description:@"The browser page closed before JavaScript evaluation completed."];
        });
      }
      browser_ = nullptr;
    }
  }

  bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefFrame> frame,
                     int popup_id,
                     const CefString &target_url,
                     const CefString &target_frame_name,
                     WindowOpenDisposition target_disposition,
                     bool user_gesture,
                     const CefPopupFeatures &popupFeatures,
                     CefWindowInfo &windowInfo,
                     CefRefPtr<CefClient> &client,
                     CefBrowserSettings &settings,
                     CefRefPtr<CefDictionaryValue> &extra_info,
                     bool *no_javascript_access) override;

  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool isLoading, bool canGoBack, bool canGoForward) override;

  void LoadURL(const std::string &url);
  void GoBack();
  void GoForward();
  void Reload();
  void ExecuteJavaScript(const std::string &script);
  bool EvaluateJavaScript(const std::string &script,
                          const std::string &request_id,
                          std::string *error_description);
  void WasResized();
  void CloseBrowser();

private:
  void EmitState(bool isLoading, bool canGoBack, bool canGoForward);

  __weak GhoDexCEFView *owner_;
  CefRefPtr<CefBrowser> browser_;

  IMPLEMENT_REFCOUNTING(GhoDexCEFClient);
};

CefRefPtr<GhoDexCEFApp> g_cef_app;
}  // namespace

@interface GhoDexCEFView () {
  CefRefPtr<GhoDexCEFClient> _client;
  NSString *_initialURLString;
  int64_t _nextEvaluationRequestID;
  NSMutableDictionary<NSString *, GhoDexCEFJavaScriptEvaluationCompletion> *_pendingEvaluationCompletions;
}
- (NSString *)registerEvaluationCompletion:(GhoDexCEFJavaScriptEvaluationCompletion)completion;
- (void)completeEvaluationRequestID:(NSString *)requestID
                         resultJSON:(NSString * _Nullable)resultJSON
                              error:(NSError * _Nullable)error;
- (void)failPendingEvaluationRequestsWithCode:(GhoDexCEFControlErrorCode)code
                                  description:(NSString *)description;
@end

@implementation GhoDexCEFView

- (instancetype)initWithInitialURLString:(NSString *)initialURLString {
  self = [super initWithFrame:NSZeroRect];
  if (self) {
    _initialURLString = [initialURLString copy];
    _pendingEvaluationCompletions = [NSMutableDictionary dictionary];
    self.wantsLayer = YES;
  }
  return self;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
  return [self initWithInitialURLString:@"about:blank"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  return [self initWithInitialURLString:@"about:blank"];
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];

  if (self.window == nil) {
    [self failPendingEvaluationRequestsWithCode:GhoDexCEFControlErrorCodeBridgeUnavailable
                                    description:@"The browser page was detached before JavaScript evaluation completed."];
    if (_client) {
      _client->CloseBrowser();
      _client = nullptr;
    }
    return;
  }

  [self ensureBrowser];
}

- (void)layout {
  [super layout];
  if (_client) {
    _client->WasResized();
  }
}

- (void)ensureBrowser {
  if (_client || !GhoDexCEFBuildHasRuntime() || !GhoDexCEFIsInitialized()) {
    return;
  }

  CefWindowInfo window_info;
  CefRect bounds(0, 0, static_cast<int>(self.bounds.size.width), static_cast<int>(self.bounds.size.height));
  window_info.SetAsChild((__bridge CefWindowHandle)self, bounds);

  CefBrowserSettings settings;
  _client = new GhoDexCEFClient(self);
  std::string initial_url(_initialURLString.UTF8String ?: "about:blank");
  BOOL created =
      CefBrowserHost::CreateBrowser(window_info, _client, initial_url, settings, nullptr, nullptr)
          ? YES
          : NO;
  if (!created) {
    NSLog(@"[CEF] CreateBrowser failed for %@", _initialURLString);
    _client = nullptr;
  } else {
    NSLog(@"[CEF] CreateBrowser requested for %@", _initialURLString);
  }
}

- (void)loadURLString:(NSString *)urlString {
  if (_client) {
    _client->LoadURL(std::string(urlString.UTF8String ?: ""));
  }
}

- (void)goBack {
  if (_client) {
    _client->GoBack();
  }
}

- (void)goForward {
  if (_client) {
    _client->GoForward();
  }
}

- (void)reloadPage {
  if (_client) {
    _client->Reload();
  }
}

- (void)executeJavaScript:(NSString *)javaScript {
  if (_client) {
    _client->ExecuteJavaScript(std::string(javaScript.UTF8String ?: ""));
  }
}

- (void)evaluateJavaScript:(NSString *)javaScript completion:(GhoDexCEFJavaScriptEvaluationCompletion)completion {
  if (_client) {
    NSString *request_id = [self registerEvaluationCompletion:completion];
    std::string error_description;
    if (_client->EvaluateJavaScript(std::string(javaScript.UTF8String ?: ""),
                                    std::string(request_id.UTF8String ?: ""),
                                    &error_description)) {
      return;
    }

    [self completeEvaluationRequestID:request_id
                           resultJSON:nil
                                error:MakeControlError(
                                          GhoDexCEFControlErrorCodeEvaluationFailed,
                                          [NSString stringWithUTF8String:error_description.c_str() ?: "The browser could not dispatch the JavaScript evaluation request."])];
    return;
  }

  if (completion != nil) {
    completion(nil, MakeControlError(GhoDexCEFControlErrorCodeBridgeUnavailable, @"The CEF browser bridge is unavailable."));
  }
}

- (void)notifyTitle:(NSString *)title {
  [self.delegate cefView:self didUpdateTitle:title];
}

- (void)notifyBridgeReady {
  [self.delegate cefViewDidBecomeReady:self];
}

- (void)notifyURL:(NSString *)url canGoBack:(BOOL)canGoBack canGoForward:(BOOL)canGoForward isLoading:(BOOL)isLoading {
  [self.delegate cefView:self didUpdateURL:url canGoBack:canGoBack canGoForward:canGoForward isLoading:isLoading];
}

- (void)notifyConsoleMessage:(NSString *)message
                       level:(NSString *)level
                      source:(NSString *)source
                        line:(NSInteger)line {
  [self.delegate cefView:self didReceiveConsoleMessage:message level:level source:source line:line];
}

- (void)notifyOpenURLInNewTab:(NSString *)urlString {
  [self.delegate cefView:self requestOpenURLInNewTab:urlString];
}

- (NSString *)registerEvaluationCompletion:(GhoDexCEFJavaScriptEvaluationCompletion)completion {
  NSString *request_id = [NSString stringWithFormat:@"%lld", ++_nextEvaluationRequestID];
  if (completion != nil) {
    _pendingEvaluationCompletions[request_id] = [completion copy];
  }
  return request_id;
}

- (void)completeEvaluationRequestID:(NSString *)requestID
                         resultJSON:(NSString *)resultJSON
                              error:(NSError *)error {
  if (requestID.length == 0) {
    return;
  }

  GhoDexCEFJavaScriptEvaluationCompletion completion = _pendingEvaluationCompletions[requestID];
  if (completion == nil) {
    return;
  }

  [_pendingEvaluationCompletions removeObjectForKey:requestID];
  completion(resultJSON, error);
}

- (void)failPendingEvaluationRequestsWithCode:(GhoDexCEFControlErrorCode)code
                                  description:(NSString *)description {
  if (_pendingEvaluationCompletions.count == 0) {
    return;
  }

  NSDictionary<NSString *, GhoDexCEFJavaScriptEvaluationCompletion> *pending =
      [_pendingEvaluationCompletions copy];
  [_pendingEvaluationCompletions removeAllObjects];

  NSError *error = MakeControlError(code, description);
  for (GhoDexCEFJavaScriptEvaluationCompletion completion in pending.objectEnumerator) {
    completion(nil, error);
  }
}

@end

namespace {
void GhoDexCEFClient::OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &title) {
  if (!owner_) {
    return;
  }

  NSString *title_string = [NSString stringWithUTF8String:title.ToString().c_str() ?: ""];
  dispatch_async(dispatch_get_main_queue(), ^{
    [owner_ notifyTitle:title_string ?: @""];
  });
}

bool GhoDexCEFClient::OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                                       cef_log_severity_t level,
                                       const CefString &message,
                                       const CefString &source,
                                       int line) {
  if (!owner_) {
    return false;
  }

  NSString *message_string = [NSString stringWithUTF8String:message.ToString().c_str() ?: ""];
  NSString *source_string = [NSString stringWithUTF8String:source.ToString().c_str() ?: ""];
  NSString *level_string = ConsoleLevelString(level);
  dispatch_async(dispatch_get_main_queue(), ^{
    [owner_ notifyConsoleMessage:message_string ?: @""
                           level:level_string ?: @"info"
                          source:source_string ?: @""
                            line:line];
  });
  return false;
}

bool GhoDexCEFClient::OnProcessMessageReceived(CefRefPtr<CefBrowser> browser,
                                               CefRefPtr<CefFrame> frame,
                                               CefProcessId source_process,
                                               CefRefPtr<CefProcessMessage> message) {
  if (source_process != PID_RENDERER || !owner_ || !message.get() ||
      message->GetName() != kEvaluateResultMessageName) {
    return false;
  }

  CefRefPtr<CefListValue> arguments = message->GetArgumentList();
  if (!arguments.get()) {
    return false;
  }

  NSString *request_id =
      [NSString stringWithUTF8String:arguments->GetString(kEvaluateRequestIDIndex).ToString().c_str() ?: ""];
  BOOL success = arguments->GetBool(kEvaluateSuccessIndex) ? YES : NO;
  NSString *payload =
      [NSString stringWithUTF8String:arguments->GetString(kEvaluatePayloadIndex).ToString().c_str() ?: ""];

  dispatch_async(dispatch_get_main_queue(), ^{
    if (success) {
      [owner_ completeEvaluationRequestID:request_id resultJSON:payload error:nil];
    } else {
      [owner_ completeEvaluationRequestID:request_id
                               resultJSON:nil
                                    error:MakeControlError(
                                              GhoDexCEFControlErrorCodeEvaluationFailed,
                                              payload.length > 0 ? payload
                                                                 : @"The renderer failed to evaluate JavaScript.")];
    }
  });
  return true;
}

void GhoDexCEFClient::OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool isLoading, bool canGoBack, bool canGoForward) {
  NSLog(@"[CEF] Loading state changed: loading=%d back=%d forward=%d url=%s",
        isLoading,
        canGoBack,
        canGoForward,
        browser ? browser->GetMainFrame()->GetURL().ToString().c_str() : "");
  if (isLoading && owner_) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [owner_ failPendingEvaluationRequestsWithCode:GhoDexCEFControlErrorCodeEvaluationUnavailable
                                        description:@"The browser page navigated before JavaScript evaluation completed."];
    });
  }
  EmitState(isLoading, canGoBack, canGoForward);
}

bool GhoDexCEFClient::OnBeforePopup(CefRefPtr<CefBrowser> browser,
                                    CefRefPtr<CefFrame> frame,
                                    int popup_id,
                                    const CefString &target_url,
                                    const CefString &target_frame_name,
                                    WindowOpenDisposition target_disposition,
                                    bool user_gesture,
                                    const CefPopupFeatures &popupFeatures,
                                    CefWindowInfo &windowInfo,
                                    CefRefPtr<CefClient> &client,
                                    CefBrowserSettings &settings,
                                    CefRefPtr<CefDictionaryValue> &extra_info,
                                    bool *no_javascript_access) {
  if (!owner_) {
    return true;
  }

  std::string requested_url = target_url.ToString();
  if (requested_url.empty()) {
    requested_url = "about:blank";
  }

  NSString *url_string = [NSString stringWithUTF8String:requested_url.c_str() ?: "about:blank"];
  NSLog(@"[CEF] Popup requested disposition=%d url=%@", static_cast<int>(target_disposition), url_string);
  dispatch_async(dispatch_get_main_queue(), ^{
    [owner_ notifyOpenURLInNewTab:url_string ?: @"about:blank"];
  });

  return true;
}

void GhoDexCEFClient::LoadURL(const std::string &url) {
  CEF_REQUIRE_UI_THREAD();
  if (browser_) {
    browser_->GetMainFrame()->LoadURL(url);
  }
}

void GhoDexCEFClient::GoBack() {
  CEF_REQUIRE_UI_THREAD();
  if (browser_ && browser_->CanGoBack()) {
    browser_->GoBack();
  }
}

void GhoDexCEFClient::GoForward() {
  CEF_REQUIRE_UI_THREAD();
  if (browser_ && browser_->CanGoForward()) {
    browser_->GoForward();
  }
}

void GhoDexCEFClient::Reload() {
  CEF_REQUIRE_UI_THREAD();
  if (browser_) {
    browser_->Reload();
  }
}

void GhoDexCEFClient::ExecuteJavaScript(const std::string &script) {
  CEF_REQUIRE_UI_THREAD();
  if (!browser_) {
    return;
  }

  CefRefPtr<CefFrame> frame = browser_->GetMainFrame();
  if (frame) {
    frame->ExecuteJavaScript(script, frame->GetURL(), 0);
  }
}

bool GhoDexCEFClient::EvaluateJavaScript(const std::string &script,
                                         const std::string &request_id,
                                         std::string *error_description) {
  CEF_REQUIRE_UI_THREAD();
  if (!browser_) {
    if (error_description != nullptr) {
      *error_description = "The CEF browser instance is not ready.";
    }
    return false;
  }

  CefRefPtr<CefFrame> frame = browser_->GetMainFrame();
  if (!frame.get()) {
    if (error_description != nullptr) {
      *error_description = "The CEF main frame is unavailable.";
    }
    return false;
  }

  CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create(kEvaluateRequestMessageName);
  CefRefPtr<CefListValue> arguments = message->GetArgumentList();
  arguments->SetString(kEvaluateRequestIDIndex, request_id);
  arguments->SetString(kEvaluateScriptIndex, script);
  frame->SendProcessMessage(PID_RENDERER, message);
  return true;
}

void GhoDexCEFClient::WasResized() {
  CEF_REQUIRE_UI_THREAD();
  if (browser_) {
    browser_->GetHost()->WasResized();
  }
}

void GhoDexCEFClient::CloseBrowser() {
  CEF_REQUIRE_UI_THREAD();
  if (browser_) {
    browser_->GetHost()->CloseBrowser(false);
    browser_ = nullptr;
  }
}

void GhoDexCEFClient::EmitState(bool isLoading, bool canGoBack, bool canGoForward) {
  if (!owner_ || !browser_) {
    return;
  }

  std::string current_url = browser_->GetMainFrame()->GetURL().ToString();
  NSString *url_string = [NSString stringWithUTF8String:current_url.c_str() ?: ""];
  dispatch_async(dispatch_get_main_queue(), ^{
    [owner_ notifyURL:url_string ?: @"" canGoBack:canGoBack canGoForward:canGoForward isLoading:isLoading];
  });
}

NSString *ValidatedDirectoryPath(NSString *candidate);

NSString *ConfiguredRuntimeRootPath(void) {
  NSString *override_path = NSProcessInfo.processInfo.environment[@"GHODEX_CEF_ROOT"];
  if (override_path.length > 0) {
    return override_path.stringByStandardizingPath;
  }

  NSString *defaults_path = [NSUserDefaults.standardUserDefaults stringForKey:@"BrowserCEFRuntimePath"];
  NSString *validated_defaults = ValidatedDirectoryPath(defaults_path);
  if (validated_defaults.length > 0) {
    return validated_defaults;
  }

  NSURL *base =
      [NSFileManager.defaultManager.homeDirectoryForCurrentUser
          URLByAppendingPathComponent:@"Library"
                         isDirectory:YES];
  base = [base URLByAppendingPathComponent:@"Application Support" isDirectory:YES];
  base = [base URLByAppendingPathComponent:@"GhoDex" isDirectory:YES];
  base = [base URLByAppendingPathComponent:@"CEF" isDirectory:YES];
  base = [base URLByAppendingPathComponent:@"current" isDirectory:YES];
  return base.path;
}

NSString *ConfiguredFrameworkDirectoryPath(void) {
  NSString *runtime_root = ConfiguredRuntimeRootPath();
  if (runtime_root.length == 0) {
    return nil;
  }

  return [[runtime_root stringByAppendingPathComponent:@"Frameworks"]
      stringByAppendingPathComponent:@"Chromium Embedded Framework.framework"];
}

NSString *ConfiguredFrameworkBinaryPath(void) {
  NSString *framework_directory = ConfiguredFrameworkDirectoryPath();
  if (framework_directory.length == 0) {
    return nil;
  }

  return [framework_directory stringByAppendingPathComponent:@"Chromium Embedded Framework"];
}

NSString *ExecutablePath(void) {
  return NSBundle.mainBundle.executablePath.stringByStandardizingPath;
}

NSString *ConfiguredHelperExecutablePath(void) {
  NSString *bundle_path = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
  if (bundle_path.length == 0) {
    return nil;
  }

  NSString *app_name = [[bundle_path.lastPathComponent stringByDeletingPathExtension] copy];
  if (app_name.length == 0) {
    return nil;
  }

  NSString *helper_name = [app_name stringByAppendingString:@" Helper"];
  NSString *helper_bundle_path =
      [[[bundle_path stringByAppendingPathComponent:@"Contents"]
             stringByAppendingPathComponent:@"Frameworks"]
            stringByAppendingPathComponent:[helper_name stringByAppendingString:@".app"]];
  NSString *helper_macos_path =
      [helper_bundle_path stringByAppendingPathComponent:@"Contents/MacOS"];
  NSString *helper_path = [helper_macos_path stringByAppendingPathComponent:helper_name];

  if (![[NSFileManager defaultManager] fileExistsAtPath:helper_path]) {
    return nil;
  }

  return helper_path;
}

NSString *ConfiguredCEFLogPath(void) {
  NSURL *base =
      [NSFileManager.defaultManager.homeDirectoryForCurrentUser
          URLByAppendingPathComponent:@"Library"
                         isDirectory:YES];
  base = [base URLByAppendingPathComponent:@"Logs" isDirectory:YES];
  base = [base URLByAppendingPathComponent:@"GhoDex" isDirectory:YES];

  NSError *error = nil;
  [NSFileManager.defaultManager createDirectoryAtURL:base
                         withIntermediateDirectories:YES
                                          attributes:nil
                                               error:&error];
  if (error != nil) {
    return nil;
  }

  return [[base URLByAppendingPathComponent:@"cef.log" isDirectory:NO] path];
}

NSString *ValidatedDirectoryPath(NSString *candidate) {
  NSString *standardized = candidate.stringByStandardizingPath;
  if (standardized.length == 0 || ![standardized isAbsolutePath]) {
    return nil;
  }

  BOOL is_directory = NO;
  if (![[NSFileManager defaultManager] fileExistsAtPath:standardized isDirectory:&is_directory] ||
      !is_directory) {
    return nil;
  }

  return standardized;
}

NSString *ConfiguredExternalProfilePath(void) {
  NSString *override_path = NSProcessInfo.processInfo.environment[@"GHODEX_CEF_PROFILE_PATH"];
  NSString *validated = ValidatedDirectoryPath(override_path);
  if (validated.length > 0) {
    return validated;
  }

  NSString *defaults_path =
      [NSUserDefaults.standardUserDefaults stringForKey:@"BrowserCEFProfilePath"];
  return ValidatedDirectoryPath(defaults_path);
}

NSString *SanitizedPathComponent(NSString *value) {
  if (value.length == 0) {
    return @"default";
  }

  NSMutableString *sanitized = [NSMutableString stringWithCapacity:value.length];
  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:
                          @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._"];
  for (NSUInteger i = 0; i < value.length; i++) {
    unichar character = [value characterAtIndex:i];
    if ([allowed characterIsMember:character]) {
      [sanitized appendFormat:@"%C", character];
    } else {
      [sanitized appendString:@"_"];
    }
  }

  return sanitized;
}

NSString *ConfiguredProfileRootPath(void) {
  NSString *external_profile = ConfiguredExternalProfilePath();
  if (external_profile.length > 0) {
    return external_profile.stringByDeletingLastPathComponent;
  }

  NSURL *base =
      [NSFileManager.defaultManager.homeDirectoryForCurrentUser
          URLByAppendingPathComponent:@"Library"
                         isDirectory:YES];
  base = [base URLByAppendingPathComponent:@"Application Support" isDirectory:YES];
  base = [base URLByAppendingPathComponent:@"GhoDex" isDirectory:YES];
  base = [base URLByAppendingPathComponent:@"CEF" isDirectory:YES];
  base = [base URLByAppendingPathComponent:@"Profiles" isDirectory:YES];
  base = [base URLByAppendingPathComponent:@"managed" isDirectory:YES];

  NSString *bundle_identifier = NSBundle.mainBundle.bundleIdentifier;
  NSString *profile_slug = SanitizedPathComponent(bundle_identifier.length > 0 ? bundle_identifier : @"managed-default");
  base = [base URLByAppendingPathComponent:profile_slug isDirectory:YES];

  NSError *error = nil;
  [NSFileManager.defaultManager createDirectoryAtURL:base
                         withIntermediateDirectories:YES
                                          attributes:nil
                                               error:&error];
  if (error != nil) {
    return nil;
  }

  return base.path;
}

NSString *ConfiguredProfileCachePath(void) {
  NSString *external_profile = ConfiguredExternalProfilePath();
  if (external_profile.length > 0) {
    // When reusing an existing Chromium-style user-data dir, keep CEF rooted at
    // the shared user-data directory and select the concrete profile via a
    // command-line switch instead of forcing CEF's managed "default" child.
    return external_profile.stringByDeletingLastPathComponent;
  }

  return [ConfiguredProfileRootPath() stringByAppendingPathComponent:@"Cache"];
}

NSString *ConfiguredProfileDirectoryName(void) {
  NSString *external_profile = ConfiguredExternalProfilePath();
  if (external_profile.length == 0) {
    return nil;
  }

  return external_profile.lastPathComponent;
}

BOOL EnsureLibraryLoaded(void) {
  if (g_cef_library_loaded.load()) {
    return YES;
  }

  NSString *framework_binary = ConfiguredFrameworkBinaryPath();
  if (framework_binary.length == 0) {
    return NO;
  }

  if (![[NSFileManager defaultManager] fileExistsAtPath:framework_binary]) {
    return NO;
  }

  BOOL loaded = cef_load_library(framework_binary.UTF8String) ? YES : NO;
  g_cef_library_loaded.store(loaded == YES);
  return loaded;
}

void GhoDexCEFApp::OnBeforeCommandLineProcessing(
    const CefString &process_type,
    CefRefPtr<CefCommandLine> command_line) {
  if (!process_type.empty()) {
    return;
  }

  NSString *external_profile = ConfiguredExternalProfilePath();
  if (external_profile.length == 0) {
    return;
  }

  NSString *user_data_dir = external_profile.stringByDeletingLastPathComponent;
  NSString *profile_directory = external_profile.lastPathComponent;
  if (user_data_dir.length == 0 || profile_directory.length == 0) {
    return;
  }

  command_line->AppendSwitchWithValue("user-data-dir", user_data_dir.UTF8String);
  command_line->AppendSwitchWithValue("profile-directory", profile_directory.UTF8String);
  NSLog(@"[CEF] Using external Chrome profile %@ (user-data-dir=%@ profile-directory=%@)",
        external_profile,
        user_data_dir,
        profile_directory);
}
}  // namespace

int GhoDexCEFExecuteProcessIfNeeded(void) {
  if (!EnsureLibraryLoaded()) {
    return -1;
  }

  ScopedMainArgs args;
  g_cef_app = new GhoDexCEFApp();
  return CefExecuteProcess(args.mainArgs(), g_cef_app.get(), nullptr);
}

BOOL GhoDexCEFInitializeGlobal(void) {
  if (g_cef_initialized.load()) {
    return YES;
  }
  bool expected_initializing = false;
  if (!g_cef_initializing.compare_exchange_strong(expected_initializing, true)) {
    return NO;
  }

  auto clear_initializing = [] {
    g_cef_initializing.store(false);
  };
  if (!EnsureLibraryLoaded()) {
    clear_initializing();
    return NO;
  }

  ScopedMainArgs args;
  if (!g_cef_app) {
    g_cef_app = new GhoDexCEFApp();
  }

  CefSettings settings;
  settings.no_sandbox = true;
  settings.external_message_pump = true;
  settings.command_line_args_disabled = false;

  NSString *bundle_path = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
  if (bundle_path.length > 0) {
    CefString(&settings.main_bundle_path) = bundle_path.UTF8String;
  }

  NSString *log_path = ConfiguredCEFLogPath();
  if (log_path.length > 0) {
    CefString(&settings.log_file) = log_path.UTF8String;
    settings.log_severity = LOGSEVERITY_INFO;
  }

  NSString *framework_path = ConfiguredFrameworkDirectoryPath();
  if (framework_path.length > 0) {
    CefString(&settings.framework_dir_path) = framework_path.UTF8String;
  }

  NSString *profile_root = ConfiguredProfileRootPath();
  if (profile_root.length > 0) {
    NSString *cache_path = ConfiguredProfileCachePath();
    CefString(&settings.root_cache_path) = profile_root.UTF8String;
    CefString(&settings.cache_path) = cache_path.UTF8String;
    settings.persist_session_cookies = true;
  }

  NSLog(@"[CEF] Initializing framework=%@ profile=%@ cache=%@ external_profile=%@ bundle=%@",
        framework_path ?: @"<none>",
        profile_root ?: @"<none>",
        ConfiguredProfileCachePath() ?: @"<none>",
        ConfiguredExternalProfilePath() ?: @"<none>",
        bundle_path ?: @"<none>");

  BOOL initialized = CefInitialize(args.mainArgs(), settings, g_cef_app.get(), nullptr) ? YES : NO;
  g_cef_initialized.store(initialized == YES);
  clear_initializing();
  if (initialized) {
    StartMessagePumpTimer();
    ScheduleMessagePumpWork(0);
  }
  return initialized;
}

void GhoDexCEFShutdownGlobal(void) {
  if (!g_cef_initialized.exchange(false)) {
    g_cef_app = nullptr;
    if (g_cef_library_loaded.exchange(false)) {
      cef_unload_library();
    }
    return;
  }

  ++g_message_pump_generation;
  StopMessagePumpTimer();
  CefShutdown();
  g_cef_app = nullptr;
  if (g_cef_library_loaded.exchange(false)) {
    cef_unload_library();
  }
}

BOOL GhoDexCEFBuildSupportsManagedRuntime(void) {
  return YES;
}

__attribute__((used)) NSString *GhoDexCEFConfiguredProfileDirectoryName(void) {
  return ConfiguredProfileDirectoryName();
}

BOOL GhoDexCEFBuildHasRuntime(void) {
  NSString *framework_path = ConfiguredFrameworkBinaryPath();
  if (framework_path.length == 0) {
    return NO;
  }

  return [[NSFileManager defaultManager] fileExistsAtPath:framework_path];
}

bool GhoDexCEFApp::OnProcessMessageReceived(CefRefPtr<CefBrowser> browser,
                                            CefRefPtr<CefFrame> frame,
                                            CefProcessId source_process,
                                            CefRefPtr<CefProcessMessage> message) {
  if (source_process != PID_BROWSER || !frame.get() || !message.get() ||
      message->GetName() != kEvaluateRequestMessageName) {
    return false;
  }

  CefRefPtr<CefListValue> arguments = message->GetArgumentList();
  if (!arguments.get()) {
    return false;
  }

  CefString request_id = arguments->GetString(kEvaluateRequestIDIndex);
  CefString script = arguments->GetString(kEvaluateScriptIndex);
  CefRefPtr<CefV8Context> context = frame->GetV8Context();
  if (!context.get() || !context->Enter()) {
    SendEvaluationResponse(frame, request_id, false, "The renderer context is not ready.");
    return true;
  }

  CefRefPtr<CefV8Value> return_value;
  CefRefPtr<CefV8Exception> exception;
  bool did_evaluate = context->Eval(script, frame->GetURL(), 0, return_value, exception);

  if (!did_evaluate) {
    context->Exit();
    std::string message_text =
        exception.get() ? exception->GetMessage().ToString() : "JavaScript evaluation failed.";
    SendEvaluationResponse(frame, request_id, false, message_text);
    return true;
  }

  if (return_value.get() && return_value->IsPromise()) {
    CefRefPtr<CefV8Value> then_function = return_value->GetValue("then");
    if (!then_function.get() || !then_function->IsFunction()) {
      context->Exit();
      SendEvaluationResponse(frame, request_id, false, "The JavaScript promise result could not be observed.");
      return true;
    }

    CefV8ValueList then_arguments;
    then_arguments.push_back(CefV8Value::CreateFunction(
        "ghodexResolveEvaluation",
        new GhoDexCEFEvaluationPromiseHandler(frame, request_id, true)));
    then_arguments.push_back(CefV8Value::CreateFunction(
        "ghodexRejectEvaluation",
        new GhoDexCEFEvaluationPromiseHandler(frame, request_id, false)));

    CefRefPtr<CefV8Value> then_result =
        then_function->ExecuteFunctionWithContext(context, return_value, then_arguments);
    context->Exit();

    if (!then_result.get()) {
      SendEvaluationResponse(frame,
                             request_id,
                             false,
                             "The JavaScript promise callbacks could not be attached.");
    }
    return true;
  }

  NSString *serialization_error = nil;
  NSString *result_json = JSONStringFromV8Value(return_value, &serialization_error);
  context->Exit();
  if (result_json.length == 0 && serialization_error != nil) {
    SendEvaluationResponse(frame,
                           request_id,
                           false,
                           std::string(serialization_error.UTF8String ?: "The renderer could not serialize the JavaScript result."));
    return true;
  }

  SendEvaluationResponse(frame,
                         request_id,
                         true,
                         std::string(result_json.UTF8String ?: "null"));
  return true;
}

BOOL GhoDexCEFIsInitialized(void) {
  return g_cef_initialized.load() ? YES : NO;
}

#else

int GhoDexCEFExecuteProcessIfNeeded(void) {
  return -1;
}

BOOL GhoDexCEFInitializeGlobal(void) {
  return NO;
}

void GhoDexCEFShutdownGlobal(void) {
}

BOOL GhoDexCEFBuildSupportsManagedRuntime(void) {
  return NO;
}

BOOL GhoDexCEFBuildHasRuntime(void) {
  return NO;
}

BOOL GhoDexCEFIsInitialized(void) {
  return NO;
}

@interface GhoDexCEFView ()
@property(nonatomic, copy) NSString *initialURLString;
@end

@implementation GhoDexCEFView

- (instancetype)initWithInitialURLString:(NSString *)initialURLString {
  self = [super initWithFrame:NSZeroRect];
  if (self) {
    _initialURLString = [initialURLString copy];
  }
  return self;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
  return [self initWithInitialURLString:@"about:blank"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  return [self initWithInitialURLString:@"about:blank"];
}

- (void)loadURLString:(NSString *)urlString {
}

- (void)goBack {
}

- (void)goForward {
}

- (void)reloadPage {
}

- (void)executeJavaScript:(NSString *)javaScript {
}

- (void)evaluateJavaScript:(NSString *)javaScript completion:(GhoDexCEFJavaScriptEvaluationCompletion)completion {
  if (completion != nil) {
    NSError *error = [NSError errorWithDomain:GhoDexCEFControlErrorDomain
                                         code:GhoDexCEFControlErrorCodeBridgeUnavailable
                                     userInfo:@{
                                       NSLocalizedDescriptionKey : @"CEF support is disabled in this build."
                                     }];
    completion(nil, error);
  }
}

@end

#endif
