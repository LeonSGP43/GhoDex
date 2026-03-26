#import "GhoDexCEFBridge.h"
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import <Security/Security.h>
#if __has_include(<UniformTypeIdentifiers/UniformTypeIdentifiers.h>)
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#endif

#include <sqlite3.h>

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
- (void)notifyNetworkRequestForURL:(NSString *)url
                            method:(NSString *)method
                     requestStatus:(NSString *)requestStatus
                        statusCode:(NSInteger)statusCode
                        statusText:(NSString *)statusText
                          mimeType:(NSString *)mimeType
             receivedContentLength:(int64_t)receivedContentLength
                       isMainFrame:(BOOL)isMainFrame
                         frameName:(NSString *)frameName;
- (void)notifyOpenURLInNewTab:(NSString *)urlString
                  disposition:(NSInteger)disposition
                  userGesture:(BOOL)userGesture;
- (void)notifyHostedPopupWindowForURL:(NSString *)urlString
                          disposition:(NSInteger)disposition
                          userGesture:(BOOL)userGesture;
- (BOOL)resolveRuntimePromptRequestID:(NSString *)requestID
                                 kind:(NSString *)kind
                              payload:(NSDictionary<NSString *, NSString *> *)payload
                                error:(NSError * _Nullable * _Nullable)error;
- (void)cancelPendingRuntimePromptRequests;
- (void)browserDidClose;
- (void)loadPendingBootstrapURLIfNeeded;
@end

#if GHODEX_CEF_ENABLED

#include <algorithm>
#include <atomic>
#include <cmath>
#include <errno.h>
#include <limits.h>
#include <libproc.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <string>
#include <vector>

#include <dispatch/dispatch.h>
#include <map>

#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_dialog_handler.h"
#include "include/cef_download_handler.h"
#include "include/cef_jsdialog_handler.h"
#include "include/cef_parser.h"
#include "include/cef_permission_handler.h"
#include "include/cef_render_process_handler.h"
#include "include/cef_v8.h"
#include "include/wrapper/cef_library_loader.h"
#include "include/wrapper/cef_helpers.h"

namespace {
std::atomic<int64_t> g_message_pump_generation{0};
std::atomic<bool> g_cef_initialized{false};
std::atomic<bool> g_cef_initializing{false};
std::atomic<bool> g_cef_library_loaded{false};
NSString *g_cef_last_initialization_error = nil;
dispatch_source_t g_message_pump_timer = nullptr;
constexpr char kEvaluateRequestMessageName[] = "ghodex.browser.evaluate";
constexpr char kEvaluateResultMessageName[] = "ghodex.browser.evaluate.result";
constexpr double kRuntimePromptExternalResolutionGraceSeconds = 0.75;

constexpr size_t kEvaluateRequestIDIndex = 0;
constexpr size_t kEvaluateScriptIndex = 1;
constexpr size_t kEvaluateSuccessIndex = 1;
constexpr size_t kEvaluatePayloadIndex = 2;

NSError *MakeControlError(GhoDexCEFControlErrorCode code, NSString *description) {
  return [NSError errorWithDomain:GhoDexCEFControlErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey : description ?: @"Unknown browser control error."}];
}

void SetLastInitializationError(NSString * _Nullable error) {
  g_cef_last_initialization_error = [error copy];
}

NSString * _Nullable CopyLastInitializationError(void) {
  return [g_cef_last_initialization_error copy];
}

BOOL HasIsolatedAppSupportRootOverride(void);
NSString *ConfiguredExternalProfilePath(void);
NSString *ConfiguredProfileRootPath(void);
NSString * _Nullable CanonicalCEFPath(NSString *path);

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

NSString *RequestStatusString(cef_urlrequest_status_t status) {
  switch (status) {
  case UR_UNKNOWN:
    return @"unknown";
  case UR_SUCCESS:
    return @"success";
  case UR_IO_PENDING:
    return @"io_pending";
  case UR_CANCELED:
    return @"canceled";
  case UR_FAILED:
    return @"failed";
  default:
    return @"unknown";
  }
}

NSWindow *PromptWindowForOwner(GhoDexCEFView *owner) {
  if (owner.window != nil) {
    return owner.window;
  }
  if (NSApp.keyWindow != nil) {
    return NSApp.keyWindow;
  }
  return NSApp.mainWindow;
}

NSString *AlertDisplayOrigin(NSString *origin) {
  return origin.length > 0 ? origin : @"this page";
}

void RunOnMainThreadSync(dispatch_block_t block) {
  if (block == nil) {
    return;
  }
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_sync(dispatch_get_main_queue(), block);
  }
}

NSModalResponse RunAlert(NSAlert *alert, GhoDexCEFView *owner) {
  __block NSModalResponse response = NSModalResponseAbort;
  RunOnMainThreadSync(^{
    NSWindow *window = PromptWindowForOwner(owner);
    [window makeKeyAndOrderFront:nil];
    response = [alert runModal];
  });
  return response;
}

NSString *SanitizedFilename(NSString *suggested_name) {
  NSString *candidate = suggested_name.lastPathComponent;
  if (candidate.length == 0) {
    candidate = @"download";
  }

  NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"/:\n\r\t"];
  NSArray<NSString *> *components = [candidate componentsSeparatedByCharactersInSet:invalid];
  NSString *joined = [[components filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]]
      componentsJoinedByString:@"-"];
  return joined.length > 0 ? joined : @"download";
}

NSURL *DownloadsDirectoryURL(void) {
  NSURL *url = [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"]
                          isDirectory:YES];
  NSError *error = nil;
  [[NSFileManager defaultManager] createDirectoryAtURL:url
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:&error];
  if (error != nil) {
    NSLog(@"[CEF] Failed to create Downloads directory %@: %@",
          url.path,
          error.localizedDescription);
  }
  return url;
}

NSURL *UniqueDownloadURL(NSString *suggested_name) {
  NSString *sanitized = SanitizedFilename(suggested_name);
  NSString *stem = sanitized.stringByDeletingPathExtension;
  NSString *ext = sanitized.pathExtension;
  NSURL *directory = DownloadsDirectoryURL();
  NSFileManager *file_manager = [NSFileManager defaultManager];

  for (NSInteger attempt = 0; attempt < 1000; attempt++) {
    NSString *filename = sanitized;
    if (attempt > 0) {
      NSString *suffix = [NSString stringWithFormat:@" (%ld)", (long)attempt];
      NSString *candidate_stem = stem.length > 0 ? [stem stringByAppendingString:suffix]
                                                 : [@"download" stringByAppendingString:suffix];
      filename = ext.length > 0 ? [candidate_stem stringByAppendingPathExtension:ext]
                                : candidate_stem;
    }

    NSURL *candidate = [directory URLByAppendingPathComponent:filename isDirectory:NO];
    if (![file_manager fileExistsAtPath:candidate.path]) {
      return candidate;
    }
  }

  return [directory URLByAppendingPathComponent:sanitized isDirectory:NO];
}

NSString *BoolString(BOOL value) {
  return value ? @"true" : @"false";
}

NSString *IntegerString(NSInteger value) {
  return [NSString stringWithFormat:@"%ld", (long)value];
}

NSString *Int64String(int64_t value) {
  return [NSString stringWithFormat:@"%lld", (long long)value];
}

NSString *UInt32String(uint32_t value) {
  return [NSString stringWithFormat:@"%u", value];
}

NSString *UInt64String(uint64_t value) {
  return [NSString stringWithFormat:@"%llu", (unsigned long long)value];
}

void SetPayloadValue(NSMutableDictionary<NSString *, NSString *> *payload,
                     NSString *key,
                     NSString * _Nullable value) {
  if (payload == nil || key.length == 0 || value == nil || value.length == 0) {
    return;
  }
  payload[key] = value;
}

NSString *JSDialogTypeName(CefJSDialogHandler::JSDialogType dialog_type) {
  switch (dialog_type) {
  case JSDIALOGTYPE_ALERT:
    return @"alert";
  case JSDIALOGTYPE_CONFIRM:
    return @"confirm";
  case JSDIALOGTYPE_PROMPT:
    return @"prompt";
  }
  return @"unknown";
}

NSArray<NSString *> *ExpandedFileDialogExtensions(
    const std::vector<CefString> &accept_filters,
    const std::vector<CefString> &accept_extensions) {
  NSMutableOrderedSet<NSString *> *extensions = [NSMutableOrderedSet orderedSet];
  auto append_value = ^(NSString *value) {
    for (NSString *part in [value componentsSeparatedByString:@";"]) {
      NSString *trimmed = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      if ([trimmed hasPrefix:@"."]) {
        trimmed = [trimmed substringFromIndex:1];
      }
      if ([trimmed containsString:@"/"] || [trimmed isEqualToString:@"*"]) {
        continue;
      }
      if (trimmed.length > 0) {
        [extensions addObject:trimmed];
      }
    }
  };

  for (const CefString &extension : accept_extensions) {
    NSString *value = [NSString stringWithUTF8String:extension.ToString().c_str() ?: ""];
    append_value(value);
  }
  for (const CefString &filter : accept_filters) {
    NSString *value = [NSString stringWithUTF8String:filter.ToString().c_str() ?: ""];
    append_value(value);
  }
  return extensions.array;
}

void ApplyFileDialogExtensions(NSSavePanel *panel, NSArray<NSString *> *allowed_extensions) {
  if (allowed_extensions.count == 0) {
    return;
  }
#if __has_include(<UniformTypeIdentifiers/UniformTypeIdentifiers.h>)
  if (@available(macOS 11.0, *)) {
    NSMutableArray<UTType *> *content_types = [NSMutableArray array];
    for (NSString *extension in allowed_extensions) {
      UTType *content_type = [UTType typeWithFilenameExtension:extension];
      if (content_type != nil) {
        [content_types addObject:content_type];
      }
    }
    if (content_types.count > 0) {
      panel.allowedContentTypes = content_types;
      return;
    }
  }
#endif
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  panel.allowedFileTypes = allowed_extensions;
#pragma clang diagnostic pop
}

NSString *MediaPermissionDescription(uint32_t requested_permissions) {
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  if ((requested_permissions & CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE) != 0) {
    [parts addObject:@"microphone"];
  }
  if ((requested_permissions & CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE) != 0) {
    [parts addObject:@"camera"];
  }
  if ((requested_permissions & CEF_MEDIA_PERMISSION_DESKTOP_AUDIO_CAPTURE) != 0) {
    [parts addObject:@"system audio capture"];
  }
  if ((requested_permissions & CEF_MEDIA_PERMISSION_DESKTOP_VIDEO_CAPTURE) != 0) {
    [parts addObject:@"screen capture"];
  }

  return parts.count > 0 ? [parts componentsJoinedByString:@", "] : @"device access";
}

void AppendPermissionTypeLabel(NSMutableArray<NSString *> *labels,
                               uint32_t requested_permissions,
                               uint32_t permission_type,
                               NSString *label) {
  if ((requested_permissions & permission_type) != 0) {
    [labels addObject:label];
  }
}

NSString *PermissionPromptDescription(uint32_t requested_permissions) {
  NSMutableArray<NSString *> *labels = [NSMutableArray array];
  AppendPermissionTypeLabel(labels, requested_permissions, CEF_PERMISSION_TYPE_GEOLOCATION, @"location");
  AppendPermissionTypeLabel(labels, requested_permissions, CEF_PERMISSION_TYPE_NOTIFICATIONS, @"notifications");
  AppendPermissionTypeLabel(labels, requested_permissions, CEF_PERMISSION_TYPE_CLIPBOARD, @"clipboard");
  AppendPermissionTypeLabel(labels, requested_permissions, CEF_PERMISSION_TYPE_POINTER_LOCK, @"pointer lock");
  AppendPermissionTypeLabel(labels, requested_permissions, CEF_PERMISSION_TYPE_KEYBOARD_LOCK, @"keyboard lock");
  AppendPermissionTypeLabel(labels, requested_permissions, CEF_PERMISSION_TYPE_CAMERA_STREAM, @"camera");
  AppendPermissionTypeLabel(labels, requested_permissions, CEF_PERMISSION_TYPE_MIC_STREAM, @"microphone");
  AppendPermissionTypeLabel(labels, requested_permissions, CEF_PERMISSION_TYPE_MULTIPLE_DOWNLOADS, @"multiple downloads");
  AppendPermissionTypeLabel(labels, requested_permissions, CEF_PERMISSION_TYPE_FILE_SYSTEM_ACCESS, @"file system access");
  AppendPermissionTypeLabel(labels, requested_permissions, CEF_PERMISSION_TYPE_WINDOW_MANAGEMENT, @"window management");
  AppendPermissionTypeLabel(labels, requested_permissions, CEF_PERMISSION_TYPE_LOCAL_FONTS, @"local fonts");
  AppendPermissionTypeLabel(labels, requested_permissions, CEF_PERMISSION_TYPE_MIDI_SYSEX, @"MIDI SysEx");
  AppendPermissionTypeLabel(labels, requested_permissions, CEF_PERMISSION_TYPE_PROTECTED_MEDIA_IDENTIFIER, @"protected media");
  AppendPermissionTypeLabel(labels, requested_permissions, CEF_PERMISSION_TYPE_STORAGE_ACCESS, @"storage access");
  AppendPermissionTypeLabel(labels, requested_permissions, CEF_PERMISSION_TYPE_TOP_LEVEL_STORAGE_ACCESS, @"top-level storage access");
#if CEF_API_ADDED(13600)
  AppendPermissionTypeLabel(labels, requested_permissions, CEF_PERMISSION_TYPE_LOCAL_NETWORK_ACCESS, @"local network access");
#endif
#if CEF_API_ADDED(14500)
  AppendPermissionTypeLabel(labels, requested_permissions, CEF_PERMISSION_TYPE_LOCAL_NETWORK, @"local network");
  AppendPermissionTypeLabel(labels, requested_permissions, CEF_PERMISSION_TYPE_LOOPBACK_NETWORK, @"loopback network");
#endif

  return labels.count > 0 ? [labels componentsJoinedByString:@", "] : @"additional browser permissions";
}

std::vector<CefString> VectorFromURLs(NSArray<NSURL *> *urls) {
  std::vector<CefString> result;
  result.reserve(urls.count);
  for (NSURL *url in urls) {
    if (url.path.length > 0) {
      result.push_back(CefString(url.path.UTF8String));
    }
  }
  return result;
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
                              public CefDialogHandler,
                              public CefDisplayHandler,
                              public CefDownloadHandler,
                              public CefJSDialogHandler,
                              public CefLifeSpanHandler,
                              public CefLoadHandler,
                              public CefPermissionHandler,
                              public CefRequestHandler,
                              public CefResourceRequestHandler {
public:
  explicit GhoDexCEFClient(GhoDexCEFView *owner) : owner_(owner) {}

  CefRefPtr<CefDialogHandler> GetDialogHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
  CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return this; }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefResourceRequestHandler> GetResourceRequestHandler(
      CefRefPtr<CefBrowser> browser,
      CefRefPtr<CefFrame> frame,
      CefRefPtr<CefRequest> request,
      bool is_navigation,
      bool is_download,
      const CefString &request_initiator,
      bool &disable_default_handling) override {
    return this;
  }
  bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser,
                                CefRefPtr<CefFrame> frame,
                                CefProcessId source_process,
                                CefRefPtr<CefProcessMessage> message) override;
  bool OnFileDialog(CefRefPtr<CefBrowser> browser,
                    FileDialogMode mode,
                    const CefString &title,
                    const CefString &default_file_path,
                    const std::vector<CefString> &accept_filters,
                    const std::vector<CefString> &accept_extensions,
                    const std::vector<CefString> &accept_descriptions,
                    CefRefPtr<CefFileDialogCallback> callback) override;
  bool CanDownload(CefRefPtr<CefBrowser> browser,
                   const CefString &url,
                   const CefString &request_method) override;
  bool OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefDownloadItem> download_item,
                        const CefString &suggested_name,
                        CefRefPtr<CefBeforeDownloadCallback> callback) override;
  void OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                         CefRefPtr<CefDownloadItem> download_item,
                         CefRefPtr<CefDownloadItemCallback> callback) override;
  bool OnJSDialog(CefRefPtr<CefBrowser> browser,
                  const CefString &origin_url,
                  CefJSDialogHandler::JSDialogType dialog_type,
                  const CefString &message_text,
                  const CefString &default_prompt_text,
                  CefRefPtr<CefJSDialogCallback> callback,
                  bool &suppress_message) override;
  bool OnBeforeUnloadDialog(CefRefPtr<CefBrowser> browser,
                            const CefString &message_text,
                            bool is_reload,
                            CefRefPtr<CefJSDialogCallback> callback) override;
  bool OnRequestMediaAccessPermission(
      CefRefPtr<CefBrowser> browser,
      CefRefPtr<CefFrame> frame,
      const CefString &requesting_origin,
      uint32_t requested_permissions,
      CefRefPtr<CefMediaAccessCallback> callback) override;
  bool OnShowPermissionPrompt(CefRefPtr<CefBrowser> browser,
                              uint64_t prompt_id,
                              const CefString &requesting_origin,
                              uint32_t requested_permissions,
                              CefRefPtr<CefPermissionPromptCallback> callback) override;

  void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &title) override;
  bool OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                        cef_log_severity_t level,
                        const CefString &message,
                        const CefString &source,
                        int line) override;
  void OnResourceLoadComplete(CefRefPtr<CefBrowser> browser,
                              CefRefPtr<CefFrame> frame,
                              CefRefPtr<CefRequest> request,
                              CefRefPtr<CefResponse> response,
                              URLRequestStatus status,
                              int64_t received_content_length) override;

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    browser_ = browser;
    NSLog(@"[CEF] Browser created for %@", owner_);
    if (owner_) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [owner_ notifyBridgeReady];
        [owner_ loadPendingBootstrapURLIfNeeded];
      });
    }
    EmitState(browser->IsLoading(), browser->CanGoBack(), browser->CanGoForward());
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    if (browser_ && browser_->GetIdentifier() == browser->GetIdentifier()) {
      pending_download_callbacks_.clear();
      if (owner_) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [owner_ failPendingEvaluationRequestsWithCode:GhoDexCEFControlErrorCodeBridgeUnavailable
                                            description:@"The browser page closed before JavaScript evaluation completed."];
          [owner_ cancelPendingRuntimePromptRequests];
          [owner_ browserDidClose];
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
  bool GetAuthCredentials(CefRefPtr<CefBrowser> browser,
                          const CefString &origin_url,
                          bool isProxy,
                          const CefString &host,
                          int port,
                          const CefString &realm,
                          const CefString &scheme,
                          CefRefPtr<CefAuthCallback> callback) override;
  bool OnCertificateError(CefRefPtr<CefBrowser> browser,
                          cef_errorcode_t cert_error,
                          const CefString &request_url,
                          CefRefPtr<CefSSLInfo> ssl_info,
                          CefRefPtr<CefCallback> callback) override;

  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool isLoading, bool canGoBack, bool canGoForward) override;

  void LoadURL(const std::string &url);
  void GoBack();
  void GoForward();
  void Reload();
  void ExecuteJavaScript(const std::string &script);
  void ExecuteJavaScript(const std::string &script,
                         const std::string *frame_name);
  bool EvaluateJavaScript(const std::string &script,
                          const std::string *frame_name,
                          const std::string &request_id,
                          std::string *error_description);
  bool ListFrames(std::string *result_json, std::string *error_description);
  bool SendTrustedClick(double x, double y, std::string *error_description);
  bool CancelDownload(uint32_t download_id, std::string *error_description);
  void WasResized();
  void CloseBrowser();

private:
  CefRefPtr<CefFrame> ResolveFrame(const std::string *frame_name,
                                   std::string *error_description);
  void EmitState(bool isLoading, bool canGoBack, bool canGoForward);

  __weak GhoDexCEFView *owner_;
  CefRefPtr<CefBrowser> browser_;
  std::map<uint32_t, CefRefPtr<CefDownloadItemCallback>> pending_download_callbacks_;

  IMPLEMENT_REFCOUNTING(GhoDexCEFClient);
};

CefRefPtr<GhoDexCEFApp> g_cef_app;
}  // namespace

@interface GhoDexCEFView (BootstrapInternal)
- (void)loadPendingBootstrapURLIfNeeded;
@end

@interface GhoDexCEFView (PopupHostingInternal)
- (CefRefPtr<GhoDexCEFClient>)preparePopupHostingClient;
@end

@interface GhoDexCEFPopupWindowController : NSWindowController <NSWindowDelegate, GhoDexCEFViewDelegate>
@property(nonatomic, strong, readonly) GhoDexCEFView *cefView;
- (instancetype)initWithSourceView:(GhoDexCEFView *)sourceView
                     popupFeatures:(const CefPopupFeatures &)popupFeatures NS_DESIGNATED_INITIALIZER;
- (void)presentPopupWindow;
@end

typedef void (^GhoDexCEFRuntimePromptContinuation)(
    NSDictionary<NSString *, NSString *> * _Nullable resolutionPayload,
    BOOL externallyResolved,
    BOOL canceled);

@interface GhoDexCEFRuntimePromptRequest : NSObject
@property(nonatomic, copy, readonly) NSString *requestID;
@property(nonatomic, copy, readonly) NSString *kind;
@property(nonatomic, strong, readonly) dispatch_semaphore_t semaphore;
@property(nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *resolutionPayload;
@property(nonatomic, copy, nullable) GhoDexCEFRuntimePromptContinuation continuation;
@property(nonatomic) BOOL externallyResolved;
@property(nonatomic) BOOL canceled;
@property(nonatomic) BOOL completed;
- (instancetype)initWithRequestID:(NSString *)requestID
                             kind:(NSString *)kind NS_DESIGNATED_INITIALIZER;
@end

@interface GhoDexCEFView () {
  CefRefPtr<GhoDexCEFClient> _client;
  NSString *_initialURLString;
  NSString *_pendingBootstrapURLString;
  BOOL _defersInitialBrowserCreation;
  BOOL _closesWindowWhenBrowserCloses;
  int64_t _nextEvaluationRequestID;
  int64_t _nextRuntimePromptRequestID;
  NSMutableDictionary<NSString *, GhoDexCEFJavaScriptEvaluationCompletion> *_pendingEvaluationCompletions;
  NSMutableDictionary<NSString *, GhoDexCEFRuntimePromptRequest *> *_pendingRuntimePromptRequests;
}
- (instancetype)initWithInitialURLString:(NSString *)initialURLString
             deferInitialBrowserCreation:(BOOL)deferInitialBrowserCreation NS_DESIGNATED_INITIALIZER;
- (NSString *)registerEvaluationCompletion:(GhoDexCEFJavaScriptEvaluationCompletion)completion;
- (void)completeEvaluationRequestID:(NSString *)requestID
                         resultJSON:(NSString * _Nullable)resultJSON
                              error:(NSError * _Nullable)error;
- (void)failPendingEvaluationRequestsWithCode:(GhoDexCEFControlErrorCode)code
                                  description:(NSString *)description;
- (GhoDexCEFRuntimePromptRequest *)beginRuntimePromptKind:(NSString *)kind
                                                  payload:(NSDictionary<NSString *, NSString *> *)payload;
- (NSDictionary<NSString *, NSString *> * _Nullable)finishRuntimePromptRequest:(GhoDexCEFRuntimePromptRequest *)request
                                                             externallyResolved:(BOOL *)externallyResolved
                                                                       canceled:(BOOL *)canceled;
- (void)resumeRuntimePromptRequest:(GhoDexCEFRuntimePromptRequest *)request;
- (void)loadPendingBootstrapURLIfNeeded;
@end

@implementation GhoDexCEFRuntimePromptRequest

- (instancetype)initWithRequestID:(NSString *)requestID kind:(NSString *)kind {
  self = [super init];
  if (self) {
    _requestID = [requestID copy];
    _kind = [kind copy];
    _semaphore = dispatch_semaphore_create(0);
    _resolutionPayload = nil;
    _continuation = nil;
    _externallyResolved = NO;
    _canceled = NO;
    _completed = NO;
  }
  return self;
}

- (instancetype)init {
  return [self initWithRequestID:@"" kind:@""];
}

@end

@implementation GhoDexCEFView

- (instancetype)initWithInitialURLString:(NSString *)initialURLString {
  return [self initWithInitialURLString:initialURLString deferInitialBrowserCreation:NO];
}

- (instancetype)initWithInitialURLString:(NSString *)initialURLString
             deferInitialBrowserCreation:(BOOL)deferInitialBrowserCreation {
  self = [super initWithFrame:NSZeroRect];
  if (self) {
    _initialURLString = [initialURLString copy];
    _pendingBootstrapURLString = nil;
    _defersInitialBrowserCreation = deferInitialBrowserCreation;
    _closesWindowWhenBrowserCloses = NO;
    _pendingEvaluationCompletions = [NSMutableDictionary dictionary];
    _pendingRuntimePromptRequests = [NSMutableDictionary dictionary];
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
    [self cancelPendingRuntimePromptRequests];
    if (_client) {
      _client->CloseBrowser();
      _client = nullptr;
    }
    return;
  }

  if (_defersInitialBrowserCreation) {
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
  NSString *initial_url_string = _initialURLString.length > 0 ? _initialURLString : @"about:blank";
  if (ConfiguredExternalProfilePath().length > 0 && ![initial_url_string isEqualToString:@"about:blank"]) {
    _pendingBootstrapURLString = [initial_url_string copy];
    initial_url_string = @"about:blank";
  } else {
    _pendingBootstrapURLString = nil;
  }
  std::string initial_url(initial_url_string.UTF8String ?: "about:blank");
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

- (void)loadPendingBootstrapURLIfNeeded {
  if (_pendingBootstrapURLString.length == 0) {
    return;
  }

  NSString *target_url = _pendingBootstrapURLString;
  _pendingBootstrapURLString = nil;
  [self loadURLString:target_url];
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
  [self executeJavaScript:javaScript frameName:nil];
}

- (void)executeJavaScript:(NSString *)javaScript frameName:(NSString *)frameName {
  if (_client) {
    std::string frame_name(frameName.UTF8String ?: "");
    _client->ExecuteJavaScript(std::string(javaScript.UTF8String ?: ""),
                               frame_name.empty() ? nullptr : &frame_name);
  }
}

- (void)evaluateJavaScript:(NSString *)javaScript completion:(GhoDexCEFJavaScriptEvaluationCompletion)completion {
  [self evaluateJavaScript:javaScript frameName:nil completion:completion];
}

- (void)evaluateJavaScript:(NSString *)javaScript
                 frameName:(NSString *)frameName
                completion:(GhoDexCEFJavaScriptEvaluationCompletion)completion {
  if (_client) {
    NSString *request_id = [self registerEvaluationCompletion:completion];
    std::string frame_name(frameName.UTF8String ?: "");
    std::string error_description;
    if (_client->EvaluateJavaScript(std::string(javaScript.UTF8String ?: ""),
                                    frame_name.empty() ? nullptr : &frame_name,
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

- (void)listFramesWithCompletion:(GhoDexCEFJavaScriptEvaluationCompletion)completion {
  if (_client) {
    std::string result_json;
    std::string error_description;
    if (_client->ListFrames(&result_json, &error_description)) {
      if (completion != nil) {
        completion([NSString stringWithUTF8String:result_json.c_str() ?: "[]"], nil);
      }
      return;
    }

    if (completion != nil) {
      completion(nil,
                 MakeControlError(
                     GhoDexCEFControlErrorCodeEvaluationFailed,
                     [NSString stringWithUTF8String:error_description.c_str() ?: "The browser could not enumerate frames."]));
    }
    return;
  }

  if (completion != nil) {
    completion(nil, MakeControlError(GhoDexCEFControlErrorCodeBridgeUnavailable, @"The CEF browser bridge is unavailable."));
  }
}

- (BOOL)performTrustedClickAtX:(double)x
                             y:(double)y
                          error:(NSError * _Nullable * _Nullable)error {
  if (!_client) {
    if (error != nil) {
      *error = MakeControlError(
          GhoDexCEFControlErrorCodeBridgeUnavailable,
          @"The CEF browser bridge is unavailable.");
    }
    return NO;
  }

  if (self.window != nil) {
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self];
  }

  std::string error_description;
  if (_client->SendTrustedClick(x, y, &error_description)) {
    return YES;
  }

  if (error != nil) {
    *error = MakeControlError(
        GhoDexCEFControlErrorCodeEvaluationFailed,
        [NSString stringWithUTF8String:error_description.c_str() ?: "The browser could not dispatch the trusted click."]);
  }
  return NO;
}

- (BOOL)resolveDialogRequestID:(NSString *)requestID
                      accepted:(BOOL)accepted
                     userInput:(NSString *)userInput
                         error:(NSError * _Nullable * _Nullable)error {
  NSMutableDictionary<NSString *, NSString *> *payload = [@{
    @"accepted": BoolString(accepted),
  } mutableCopy];
  SetPayloadValue(payload, @"userInput", userInput);
  return [self resolveRuntimePromptRequestID:requestID
                                        kind:@"javaScriptDialog"
                                     payload:payload
                                       error:error];
}

- (BOOL)resolvePermissionRequestID:(NSString *)requestID
                            result:(NSString *)result
                             error:(NSError * _Nullable * _Nullable)error {
  NSDictionary<NSString *, NSString *> *payload = @{
    @"result": result ?: @"",
  };
  return [self resolveRuntimePromptRequestID:requestID
                                        kind:@"permissionRequest"
                                     payload:payload
                                       error:error];
}

- (BOOL)resolveAuthRequestID:(NSString *)requestID
                    accepted:(BOOL)accepted
                    username:(NSString *)username
                    password:(NSString *)password
                       error:(NSError * _Nullable * _Nullable)error {
  NSMutableDictionary<NSString *, NSString *> *payload = [@{
    @"accepted": BoolString(accepted),
  } mutableCopy];
  SetPayloadValue(payload, @"username", username);
  SetPayloadValue(payload, @"password", password);
  return [self resolveRuntimePromptRequestID:requestID
                                        kind:@"authenticationRequest"
                                     payload:payload
                                       error:error];
}

- (BOOL)resolveCertificateRequestID:(NSString *)requestID
                           accepted:(BOOL)accepted
                              error:(NSError * _Nullable * _Nullable)error {
  NSDictionary<NSString *, NSString *> *payload = @{
    @"accepted": BoolString(accepted),
  };
  return [self resolveRuntimePromptRequestID:requestID
                                        kind:@"certificateWarning"
                                     payload:payload
                                       error:error];
}

- (BOOL)cancelDownloadID:(NSString *)downloadID
                   error:(NSError * _Nullable * _Nullable)error {
  if (!_client) {
    if (error != nil) {
      *error = MakeControlError(
          GhoDexCEFControlErrorCodeBridgeUnavailable,
          @"The CEF browser bridge is unavailable.");
    }
    return NO;
  }

  NSString *trimmed_download_id = [downloadID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (trimmed_download_id.length == 0) {
    if (error != nil) {
      *error = MakeControlError(
          GhoDexCEFControlErrorCodeDownloadUnavailable,
          @"The downloadID payload is required.");
    }
    return NO;
  }

  uint64_t parsed_download_id = 0;
  NSScanner *scanner = [NSScanner scannerWithString:trimmed_download_id];
  if (![scanner scanUnsignedLongLong:&parsed_download_id] || !scanner.isAtEnd || parsed_download_id > UINT32_MAX) {
    if (error != nil) {
      *error = MakeControlError(
          GhoDexCEFControlErrorCodeDownloadUnavailable,
          @"The downloadID payload must be a valid download identifier.");
    }
    return NO;
  }

  std::string error_description;
  if (_client->CancelDownload(static_cast<uint32_t>(parsed_download_id), &error_description)) {
    return YES;
  }

  if (error != nil) {
    *error = MakeControlError(
        GhoDexCEFControlErrorCodeDownloadUnavailable,
        [NSString stringWithUTF8String:error_description.c_str() ?: "The browser could not cancel the requested download."]);
  }
  return NO;
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

- (void)notifyNetworkRequestForURL:(NSString *)url
                            method:(NSString *)method
                     requestStatus:(NSString *)requestStatus
                        statusCode:(NSInteger)statusCode
                        statusText:(NSString *)statusText
                          mimeType:(NSString *)mimeType
             receivedContentLength:(int64_t)receivedContentLength
                       isMainFrame:(BOOL)isMainFrame
                         frameName:(NSString *)frameName {
  [self.delegate cefView:self
      didFinishNetworkRequestForURL:url
                             method:method
                      requestStatus:requestStatus
                         statusCode:statusCode
                         statusText:statusText
                           mimeType:mimeType
              receivedContentLength:receivedContentLength
                        isMainFrame:isMainFrame
                          frameName:frameName];
}

- (void)notifyOpenURLInNewTab:(NSString *)urlString
                  disposition:(NSInteger)disposition
                  userGesture:(BOOL)userGesture {
  [self.delegate cefView:self
  requestOpenURLInNewTab:urlString
             disposition:disposition
              userGesture:userGesture];
}

- (void)notifyHostedPopupWindowForURL:(NSString *)urlString
                          disposition:(NSInteger)disposition
                          userGesture:(BOOL)userGesture {
  [self.delegate cefView:self
  didHostPopupWindowForURL:urlString
             disposition:disposition
              userGesture:userGesture];
}

- (void)notifyRuntimeEventKind:(NSString *)kind
                       payload:(NSDictionary<NSString *, NSString *> *)payload {
  NSDictionary<NSString *, NSString *> *captured_payload = payload ?: @{};
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.delegate cefView:self didEmitRuntimeEventKind:kind payload:captured_payload];
  });
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

- (GhoDexCEFRuntimePromptRequest *)beginRuntimePromptKind:(NSString *)kind
                                                  payload:(NSDictionary<NSString *, NSString *> *)payload {
  NSString *request_id = [NSString stringWithFormat:@"runtime-%lld", ++_nextRuntimePromptRequestID];
  GhoDexCEFRuntimePromptRequest *request =
      [[GhoDexCEFRuntimePromptRequest alloc] initWithRequestID:request_id kind:kind];
  _pendingRuntimePromptRequests[request_id] = request;

  NSMutableDictionary<NSString *, NSString *> *captured_payload =
      payload != nil ? [payload mutableCopy] : [NSMutableDictionary dictionary];
  captured_payload[@"requestID"] = request_id;
  [self notifyRuntimeEventKind:kind payload:captured_payload];
  return request;
}

- (NSDictionary<NSString *, NSString *> * _Nullable)finishRuntimePromptRequest:(GhoDexCEFRuntimePromptRequest *)request
                                                             externallyResolved:(BOOL *)externallyResolved
                                                                       canceled:(BOOL *)canceled {
  if (request == nil) {
    if (externallyResolved != nullptr) {
      *externallyResolved = NO;
    }
    if (canceled != nullptr) {
      *canceled = NO;
    }
    return nil;
  }

  [_pendingRuntimePromptRequests removeObjectForKey:request.requestID];

  @synchronized(request) {
    request.completed = YES;
    if (externallyResolved != nullptr) {
      *externallyResolved = request.externallyResolved;
    }
    if (canceled != nullptr) {
      *canceled = request.canceled;
    }
    return request.resolutionPayload;
  }
}

- (void)resumeRuntimePromptRequest:(GhoDexCEFRuntimePromptRequest *)request {
  if (request == nil) {
    return;
  }

  __block GhoDexCEFRuntimePromptContinuation continuation = nil;
  __block NSDictionary<NSString *, NSString *> *resolution_payload = nil;
  __block BOOL externally_resolved = NO;
  __block BOOL canceled = NO;

  @synchronized(request) {
    if (request.completed) {
      return;
    }
    request.completed = YES;
    continuation = [request.continuation copy];
    resolution_payload = request.resolutionPayload;
    externally_resolved = request.externallyResolved;
    canceled = request.canceled;
  }

  [_pendingRuntimePromptRequests removeObjectForKey:request.requestID];
  if (continuation != nil) {
    continuation(resolution_payload, externally_resolved, canceled);
  } else {
    dispatch_semaphore_signal(request.semaphore);
  }
}

- (BOOL)resolveRuntimePromptRequestID:(NSString *)requestID
                                 kind:(NSString *)kind
                              payload:(NSDictionary<NSString *, NSString *> *)payload
                                error:(NSError * _Nullable * _Nullable)error {
  if (requestID.length == 0) {
    if (error != nullptr) {
      *error = MakeControlError(
          GhoDexCEFControlErrorCodeRuntimePromptUnavailable,
          @"The runtime prompt requestID is required.");
    }
    return NO;
  }

  GhoDexCEFRuntimePromptRequest *request = _pendingRuntimePromptRequests[requestID];
  if (request == nil || ![request.kind isEqualToString:kind]) {
    if (error != nullptr) {
      *error = MakeControlError(
          GhoDexCEFControlErrorCodeRuntimePromptUnavailable,
          [NSString stringWithFormat:@"The runtime prompt %@ is no longer pending for %@.", requestID, kind]);
    }
    return NO;
  }

  BOOL uses_async_continuation = NO;
  @synchronized(request) {
    if (request.externallyResolved || request.canceled) {
      if (error != nullptr) {
        *error = MakeControlError(
            GhoDexCEFControlErrorCodeRuntimePromptUnavailable,
            [NSString stringWithFormat:@"The runtime prompt %@ can no longer be resolved.", requestID]);
      }
      return NO;
    }

    request.externallyResolved = YES;
    request.resolutionPayload = payload != nil ? [payload copy] : @{};
    uses_async_continuation = (request.continuation != nil);
  }

  if (uses_async_continuation) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self resumeRuntimePromptRequest:request];
    });
  } else {
    dispatch_semaphore_signal(request.semaphore);
  }
  return YES;
}

- (void)cancelPendingRuntimePromptRequests {
  if (_pendingRuntimePromptRequests.count == 0) {
    return;
  }

  NSArray<GhoDexCEFRuntimePromptRequest *> *pending = _pendingRuntimePromptRequests.allValues;
  [_pendingRuntimePromptRequests removeAllObjects];

  for (GhoDexCEFRuntimePromptRequest *request in pending) {
    BOOL uses_async_continuation = NO;
    @synchronized(request) {
      request.canceled = YES;
      request.resolutionPayload = nil;
      uses_async_continuation = (request.continuation != nil);
    }
    if (uses_async_continuation) {
      [self resumeRuntimePromptRequest:request];
    } else {
      dispatch_semaphore_signal(request.semaphore);
    }
  }
}

- (CefRefPtr<GhoDexCEFClient>)preparePopupHostingClient {
  if (!_client) {
    _client = new GhoDexCEFClient(self);
  }
  _defersInitialBrowserCreation = NO;
  _pendingBootstrapURLString = nil;
  _closesWindowWhenBrowserCloses = YES;
  return _client;
}

- (void)browserDidClose {
  if (!_closesWindowWhenBrowserCloses) {
    return;
  }

  _closesWindowWhenBrowserCloses = NO;
  if (self.window != nil) {
    [self.window close];
  }
}

@end

namespace {
NSMutableSet<GhoDexCEFPopupWindowController *> *PopupWindowControllers(void) {
  static NSMutableSet<GhoDexCEFPopupWindowController *> *controllers = nil;
  static dispatch_once_t once_token;
  dispatch_once(&once_token, ^{
    controllers = [NSMutableSet set];
  });
  return controllers;
}

void RegisterPopupWindowController(GhoDexCEFPopupWindowController *controller) {
  if (controller != nil) {
    [PopupWindowControllers() addObject:controller];
  }
}

void UnregisterPopupWindowController(GhoDexCEFPopupWindowController *controller) {
  if (controller != nil) {
    [PopupWindowControllers() removeObject:controller];
  }
}

NSRect PopupWindowFrameForSourceView(GhoDexCEFView *sourceView, const CefPopupFeatures &popupFeatures) {
  constexpr CGFloat kDefaultWidth = 960;
  constexpr CGFloat kDefaultHeight = 720;

  NSWindow *source_window = sourceView.window ?: NSApp.keyWindow ?: NSApp.mainWindow;
  NSRect source_frame = source_window != nil
      ? source_window.frame
      : NSMakeRect(160, 160, kDefaultWidth, kDefaultHeight);

  CGFloat width = popupFeatures.widthSet ? MAX(320, popupFeatures.width) : kDefaultWidth;
  CGFloat height = popupFeatures.heightSet ? MAX(240, popupFeatures.height) : kDefaultHeight;
  CGFloat x = popupFeatures.xSet ? popupFeatures.x : NSMidX(source_frame) - (width / 2.0);
  CGFloat y = popupFeatures.ySet ? popupFeatures.y : NSMidY(source_frame) - (height / 2.0);
  return NSMakeRect(x, y, width, height);
}

NSInteger RoutedDispositionForPopupFollowup(NSInteger disposition) {
  switch (disposition) {
  case CEF_WOD_NEW_BACKGROUND_TAB:
    // Popup-hosted follow-up opens have no visible tab strip of their own.
    // Promote background-tab requests so the resulting internal page is surfaced.
    return CEF_WOD_NEW_FOREGROUND_TAB;
  default:
    return disposition;
  }
}
}  // namespace

@implementation GhoDexCEFPopupWindowController {
  GhoDexCEFView *_cefView;
  __weak GhoDexCEFView *_sourceView;
}

- (instancetype)initWithSourceView:(GhoDexCEFView *)sourceView
                     popupFeatures:(const CefPopupFeatures &)popupFeatures {
  NSRect frame = PopupWindowFrameForSourceView(sourceView, popupFeatures);
  NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                 styleMask:(NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable |
                                                            NSWindowStyleMaskMiniaturizable |
                                                            NSWindowStyleMaskResizable)
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
  self = [super initWithWindow:window];
  if (self) {
    _sourceView = sourceView;
    _cefView = [[GhoDexCEFView alloc] initWithInitialURLString:@"about:blank"
                                  deferInitialBrowserCreation:YES];
    _cefView.delegate = self;
    _cefView.frame = window.contentView.bounds;
    _cefView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    window.contentView = _cefView;
    window.delegate = self;
    window.title = @"Browser Popup";
  }
  return self;
}

- (instancetype)initWithWindow:(NSWindow *)window {
  (void)window;
  return [self initWithSourceView:nil popupFeatures:CefPopupFeatures()];
}

- (GhoDexCEFView *)cefView {
  return _cefView;
}

- (void)presentPopupWindow {
  [self showWindow:nil];
  [self.window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  RegisterPopupWindowController(self);
}

- (void)windowWillClose:(NSNotification *)notification {
  (void)notification;
  UnregisterPopupWindowController(self);
}

- (void)cefViewDidBecomeReady:(GhoDexCEFView *)view {
  (void)view;
}

- (void)cefView:(GhoDexCEFView *)view didUpdateTitle:(NSString *)title {
  (void)view;
  self.window.title = title.length > 0 ? title : @"Browser Popup";
}

- (void)cefView:(GhoDexCEFView *)view
    didUpdateURL:(NSString *)url
       canGoBack:(BOOL)canGoBack
    canGoForward:(BOOL)canGoForward
       isLoading:(BOOL)isLoading {
  (void)view;
  (void)url;
  (void)canGoBack;
  (void)canGoForward;
  (void)isLoading;
}

- (void)cefView:(GhoDexCEFView *)view
    didReceiveConsoleMessage:(NSString *)message
                       level:(NSString *)level
                      source:(NSString *)source
                        line:(NSInteger)line {
  (void)view;
  (void)message;
  (void)level;
  (void)source;
  (void)line;
}

- (void)cefView:(GhoDexCEFView *)view
    didFinishNetworkRequestForURL:(NSString *)url
                           method:(NSString *)method
                    requestStatus:(NSString *)requestStatus
                       statusCode:(NSInteger)statusCode
                       statusText:(NSString *)statusText
                         mimeType:(NSString *)mimeType
            receivedContentLength:(int64_t)receivedContentLength
                      isMainFrame:(BOOL)isMainFrame
                        frameName:(NSString *)frameName {
  (void)view;
  (void)url;
  (void)method;
  (void)requestStatus;
  (void)statusCode;
  (void)statusText;
  (void)mimeType;
  (void)receivedContentLength;
  (void)isMainFrame;
  (void)frameName;
}

- (void)cefView:(GhoDexCEFView *)view
requestOpenURLInNewTab:(NSString *)urlString
    disposition:(NSInteger)disposition
     userGesture:(BOOL)userGesture {
  (void)view;
  if (_sourceView != nil) {
    NSInteger routed_disposition = RoutedDispositionForPopupFollowup(disposition);
    if (routed_disposition != disposition) {
      NSLog(@"[CEF] Promoting popup follow-up disposition=%ld to visible disposition=%ld for %@",
            (long)disposition,
            (long)routed_disposition,
            urlString);
    }
    [_sourceView notifyOpenURLInNewTab:urlString
                           disposition:routed_disposition
                           userGesture:userGesture];
    if (_sourceView.window != nil &&
        (routed_disposition == CEF_WOD_CURRENT_TAB ||
         routed_disposition == CEF_WOD_SINGLETON_TAB ||
         routed_disposition == CEF_WOD_NEW_FOREGROUND_TAB ||
         routed_disposition == CEF_WOD_SWITCH_TO_TAB)) {
      [_sourceView.window makeKeyAndOrderFront:nil];
      [NSApp activateIgnoringOtherApps:YES];
    }
    return;
  }

  NSURL *url = [NSURL URLWithString:urlString];
  if (url != nil) {
    NSLog(@"[CEF] Popup host missing source view; delegating follow-up open to NSWorkspace for %@",
          url.absoluteString ?: urlString);
    [NSWorkspace.sharedWorkspace openURL:url];
  }
}

- (void)cefView:(GhoDexCEFView *)view
didHostPopupWindowForURL:(NSString *)urlString
    disposition:(NSInteger)disposition
     userGesture:(BOOL)userGesture {
  (void)view;
  if (_sourceView != nil) {
    [_sourceView notifyHostedPopupWindowForURL:urlString
                                   disposition:disposition
                                   userGesture:userGesture];
  }
}

- (void)cefView:(GhoDexCEFView *)view
didEmitRuntimeEventKind:(NSString *)kind
        payload:(NSDictionary<NSString *, NSString *> *)payload {
  (void)view;
  (void)kind;
  (void)payload;
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

void GhoDexCEFClient::OnResourceLoadComplete(CefRefPtr<CefBrowser> browser,
                                             CefRefPtr<CefFrame> frame,
                                             CefRefPtr<CefRequest> request,
                                             CefRefPtr<CefResponse> response,
                                             URLRequestStatus status,
                                             int64_t received_content_length) {
  if (!owner_ || !request.get()) {
    return;
  }

  NSString *url_string = [NSString stringWithUTF8String:request->GetURL().ToString().c_str() ?: ""];
  NSString *method_string = [NSString stringWithUTF8String:request->GetMethod().ToString().c_str() ?: "GET"];
  NSString *request_status_string = RequestStatusString(status);
  NSString *status_text = @"";
  NSString *mime_type = @"";
  NSInteger status_code = 0;
  if (response.get()) {
    status_code = response->GetStatus();
    status_text = [NSString stringWithUTF8String:response->GetStatusText().ToString().c_str() ?: ""];
    mime_type = [NSString stringWithUTF8String:response->GetMimeType().ToString().c_str() ?: ""];
  }

  BOOL is_main_frame = frame.get() ? (frame->IsMain() ? YES : NO) : NO;
  NSString *frame_name = @"";
  if (frame.get()) {
    frame_name = [NSString stringWithUTF8String:frame->GetName().ToString().c_str() ?: ""];
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    [owner_ notifyNetworkRequestForURL:url_string ?: @""
                                method:method_string ?: @"GET"
                         requestStatus:request_status_string ?: @"unknown"
                            statusCode:status_code
                            statusText:status_text ?: @""
                              mimeType:mime_type ?: @""
                 receivedContentLength:received_content_length
                           isMainFrame:is_main_frame
                             frameName:frame_name ?: @""];
  });
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

bool GhoDexCEFClient::OnFileDialog(CefRefPtr<CefBrowser> browser,
                                   FileDialogMode mode,
                                   const CefString &title,
                                   const CefString &default_file_path,
                                   const std::vector<CefString> &accept_filters,
                                   const std::vector<CefString> &accept_extensions,
                                   const std::vector<CefString> &accept_descriptions,
                                   CefRefPtr<CefFileDialogCallback> callback) {
  (void)browser;
  (void)accept_filters;
  (void)accept_descriptions;
  if (!callback.get()) {
    return false;
  }

  NSString *dialog_title = [NSString stringWithUTF8String:title.ToString().c_str() ?: ""];
  NSString *default_path = [NSString stringWithUTF8String:default_file_path.ToString().c_str() ?: ""];
  NSArray<NSString *> *allowed_extensions = ExpandedFileDialogExtensions(accept_filters, accept_extensions);

  if (mode == FILE_DIALOG_SAVE) {
    __block NSURL *selected_url = nil;
    __block NSModalResponse response = NSModalResponseCancel;
    RunOnMainThreadSync(^{
      NSSavePanel *panel = [NSSavePanel savePanel];
      panel.title = dialog_title.length > 0 ? dialog_title : @"Save File";
      panel.canCreateDirectories = YES;
      if (default_path.length > 0) {
        NSURL *url = [NSURL fileURLWithPath:default_path];
        panel.directoryURL = url.URLByDeletingLastPathComponent;
        panel.nameFieldStringValue = url.lastPathComponent ?: @"";
      }
      ApplyFileDialogExtensions(panel, allowed_extensions);
      response = [panel runModal];
      selected_url = panel.URL;
    });
    if (response == NSModalResponseOK && selected_url.path.length > 0) {
      std::vector<CefString> selection;
      selection.push_back(CefString(selected_url.path.UTF8String));
      callback->Continue(selection);
    } else {
      callback->Cancel();
    }
    return true;
  }

  __block NSArray<NSURL *> *selected_urls = @[];
  __block NSModalResponse response = NSModalResponseCancel;
  RunOnMainThreadSync(^{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = dialog_title.length > 0 ? dialog_title : @"Choose File";
    panel.canChooseFiles = mode != FILE_DIALOG_OPEN_FOLDER;
    panel.canChooseDirectories = mode == FILE_DIALOG_OPEN_FOLDER;
    panel.allowsMultipleSelection = mode == FILE_DIALOG_OPEN_MULTIPLE;
    if (default_path.length > 0) {
      NSURL *url = [NSURL fileURLWithPath:default_path];
      panel.directoryURL = [url hasDirectoryPath] ? url : url.URLByDeletingLastPathComponent;
    }
    if (mode != FILE_DIALOG_OPEN_FOLDER) {
      ApplyFileDialogExtensions(panel, allowed_extensions);
    }
    response = [panel runModal];
    selected_urls = panel.URLs ?: @[];
  });

  if (response == NSModalResponseOK) {
    callback->Continue(VectorFromURLs(selected_urls));
  } else {
    callback->Cancel();
  }
  return true;
}

bool GhoDexCEFClient::CanDownload(CefRefPtr<CefBrowser> browser,
                                  const CefString &url,
                                  const CefString &request_method) {
  (void)browser;
  (void)url;
  (void)request_method;
  return true;
}

bool GhoDexCEFClient::OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                                       CefRefPtr<CefDownloadItem> download_item,
                                       const CefString &suggested_name,
                                       CefRefPtr<CefBeforeDownloadCallback> callback) {
  (void)browser;
  if (!callback.get()) {
    return false;
  }

  NSString *suggested = [NSString stringWithUTF8String:suggested_name.ToString().c_str() ?: ""];
  NSURL *target_url = UniqueDownloadURL(suggested);
  NSLog(@"[CEF] Download starting suggested=%@ target=%@",
        suggested.length > 0 ? suggested : @"<none>",
        target_url.path ?: @"<none>");
  if (owner_) {
    NSMutableDictionary<NSString *, NSString *> *payload = [@{
      @"phase": @"started",
      @"downloadID": download_item.get() ? UInt32String(download_item->GetId()) : @"0",
      @"url": download_item.get() ? [NSString stringWithUTF8String:download_item->GetURL().ToString().c_str() ?: ""] : @"",
      @"receivedBytes": @"0",
      @"totalBytes": download_item.get() ? Int64String(download_item->GetTotalBytes()) : @"0",
      @"percentComplete": download_item.get() ? IntegerString(download_item->GetPercentComplete()) : @"0",
      @"isComplete": @"false",
      @"isCanceled": @"false",
      @"isInterrupted": @"false",
    } mutableCopy];
    SetPayloadValue(payload, @"suggestedName", suggested);
    SetPayloadValue(payload, @"targetPath", target_url.path);
    if (download_item.get()) {
      SetPayloadValue(payload, @"mimeType", [NSString stringWithUTF8String:download_item->GetMimeType().ToString().c_str() ?: ""]);
    }
    [owner_ notifyRuntimeEventKind:@"download" payload:payload];
  }
  callback->Continue(CefString(target_url.path.UTF8String), false);
  return true;
}

void GhoDexCEFClient::OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                                        CefRefPtr<CefDownloadItem> download_item,
                                        CefRefPtr<CefDownloadItemCallback> callback) {
  (void)browser;
  if (!download_item.get()) {
    return;
  }

  const uint32_t download_id = download_item->GetId();
  if (callback.get() && !download_item->IsComplete() && !download_item->IsCanceled() &&
      !download_item->IsInterrupted()) {
    pending_download_callbacks_[download_id] = callback;
  } else {
    pending_download_callbacks_.erase(download_id);
  }

  NSString *phase = nil;
  if (download_item->IsComplete()) {
    phase = @"completed";
    NSString *path = [NSString stringWithUTF8String:download_item->GetFullPath().ToString().c_str() ?: ""];
    NSLog(@"[CEF] Download completed path=%@", path ?: @"<none>");
  } else if (download_item->IsCanceled()) {
    phase = @"canceled";
    NSLog(@"[CEF] Download canceled id=%u", download_id);
  } else if (download_item->IsInterrupted()) {
    phase = @"interrupted";
    NSLog(@"[CEF] Download interrupted id=%u", download_id);
  }

  if (phase != nil && owner_) {
    NSMutableDictionary<NSString *, NSString *> *payload = [@{
      @"phase": phase,
      @"downloadID": UInt32String(download_id),
      @"url": [NSString stringWithUTF8String:download_item->GetURL().ToString().c_str() ?: ""],
      @"receivedBytes": Int64String(download_item->GetReceivedBytes()),
      @"totalBytes": Int64String(download_item->GetTotalBytes()),
      @"percentComplete": IntegerString(download_item->GetPercentComplete()),
      @"isComplete": BoolString(download_item->IsComplete()),
      @"isCanceled": BoolString(download_item->IsCanceled()),
      @"isInterrupted": BoolString(download_item->IsInterrupted()),
    } mutableCopy];
    SetPayloadValue(payload, @"suggestedName", [NSString stringWithUTF8String:download_item->GetSuggestedFileName().ToString().c_str() ?: ""]);
    SetPayloadValue(payload, @"targetPath", [NSString stringWithUTF8String:download_item->GetFullPath().ToString().c_str() ?: ""]);
    SetPayloadValue(payload, @"mimeType", [NSString stringWithUTF8String:download_item->GetMimeType().ToString().c_str() ?: ""]);
    [owner_ notifyRuntimeEventKind:@"download" payload:payload];
  }
}

bool GhoDexCEFClient::CancelDownload(uint32_t download_id,
                                     std::string *error_description) {
  CEF_REQUIRE_UI_THREAD();
  if (!browser_) {
    if (error_description != nullptr) {
      *error_description = "The CEF browser instance is not ready.";
    }
    return false;
  }

  auto callback_it = pending_download_callbacks_.find(download_id);
  if (callback_it == pending_download_callbacks_.end() || !callback_it->second.get()) {
    if (error_description != nullptr) {
      *error_description = "No active browser download matches the requested downloadID.";
    }
    return false;
  }

  callback_it->second->Cancel();
  pending_download_callbacks_.erase(callback_it);
  return true;
}

bool GhoDexCEFClient::OnJSDialog(CefRefPtr<CefBrowser> browser,
                                 const CefString &origin_url,
                                 CefJSDialogHandler::JSDialogType dialog_type,
                                 const CefString &message_text,
                                 const CefString &default_prompt_text,
                                 CefRefPtr<CefJSDialogCallback> callback,
                                 bool &suppress_message) {
  (void)browser;
  if (!owner_ || !callback.get()) {
    return false;
  }

  suppress_message = false;
  NSString *origin = [NSString stringWithUTF8String:origin_url.ToString().c_str() ?: ""];
  NSString *message = [NSString stringWithUTF8String:message_text.ToString().c_str() ?: ""];
  NSString *default_prompt = [NSString stringWithUTF8String:default_prompt_text.ToString().c_str() ?: ""];
  NSString *dialog_type_name = JSDialogTypeName(dialog_type);

  NSMutableDictionary<NSString *, NSString *> *requested_payload = [@{
    @"phase": @"requested",
    @"dialogType": dialog_type_name,
    @"messageText": message,
  } mutableCopy];
  SetPayloadValue(requested_payload, @"originURL", origin);
  SetPayloadValue(requested_payload, @"defaultPromptText", default_prompt);
  __block GhoDexCEFRuntimePromptRequest *request = nil;
  CefRefPtr<CefJSDialogCallback> retained_callback = callback;
  RunOnMainThreadSync(^{
    request = [owner_ beginRuntimePromptKind:@"javaScriptDialog" payload:requested_payload];
    if (request != nil) {
      request.continuation = ^(NSDictionary<NSString *, NSString *> *resolution_payload,
                               BOOL externally_resolved,
                               BOOL canceled) {
        if (!owner_ || !retained_callback.get()) {
          return;
        }

        if (canceled) {
          retained_callback->Continue(false, CefString());
          return;
        }

        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleInformational;
        alert.informativeText = message.length > 0 ? message : AlertDisplayOrigin(origin);

        switch (dialog_type) {
        case JSDIALOGTYPE_ALERT: {
          if (externally_resolved) {
            BOOL accepted = [resolution_payload[@"accepted"] isEqualToString:@"true"];
            retained_callback->Continue(accepted, CefString());
            [owner_ notifyRuntimeEventKind:@"javaScriptDialog" payload:@{
              @"requestID": request.requestID,
              @"phase": @"resolved",
              @"dialogType": dialog_type_name,
              @"messageText": message,
              @"accepted": BoolString(accepted),
              @"originURL": origin ?: @"",
            }];
            return;
          }

          alert.messageText = [NSString stringWithFormat:@"%@ says", AlertDisplayOrigin(origin)];
          [alert addButtonWithTitle:@"OK"];
          BOOL accepted = RunAlert(alert, owner_) == NSAlertFirstButtonReturn;
          retained_callback->Continue(accepted, CefString());
          [owner_ notifyRuntimeEventKind:@"javaScriptDialog" payload:@{
            @"requestID": request.requestID,
            @"phase": @"resolved",
            @"dialogType": dialog_type_name,
            @"messageText": message,
            @"accepted": BoolString(accepted),
            @"originURL": origin ?: @"",
          }];
          return;
        }
        case JSDIALOGTYPE_CONFIRM: {
          if (externally_resolved) {
            BOOL accepted = [resolution_payload[@"accepted"] isEqualToString:@"true"];
            retained_callback->Continue(accepted, CefString());
            [owner_ notifyRuntimeEventKind:@"javaScriptDialog" payload:@{
              @"requestID": request.requestID,
              @"phase": @"resolved",
              @"dialogType": dialog_type_name,
              @"messageText": message,
              @"accepted": BoolString(accepted),
              @"originURL": origin ?: @"",
            }];
            return;
          }

          alert.messageText = [NSString stringWithFormat:@"%@ confirmation", AlertDisplayOrigin(origin)];
          [alert addButtonWithTitle:@"OK"];
          [alert addButtonWithTitle:@"Cancel"];
          BOOL accepted = RunAlert(alert, owner_) == NSAlertFirstButtonReturn;
          retained_callback->Continue(accepted, CefString());
          [owner_ notifyRuntimeEventKind:@"javaScriptDialog" payload:@{
            @"requestID": request.requestID,
            @"phase": @"resolved",
            @"dialogType": dialog_type_name,
            @"messageText": message,
            @"accepted": BoolString(accepted),
            @"originURL": origin ?: @"",
          }];
          return;
        }
        case JSDIALOGTYPE_PROMPT: {
          if (externally_resolved) {
            BOOL accepted = [resolution_payload[@"accepted"] isEqualToString:@"true"];
            NSString *resolved_input = accepted ? (resolution_payload[@"userInput"] ?: default_prompt) : default_prompt;
            retained_callback->Continue(accepted, CefString(resolved_input.UTF8String));
            NSMutableDictionary<NSString *, NSString *> *resolved_payload = [@{
              @"requestID": request.requestID,
              @"phase": @"resolved",
              @"dialogType": dialog_type_name,
              @"messageText": message,
              @"accepted": BoolString(accepted),
              @"originURL": origin ?: @"",
            } mutableCopy];
            SetPayloadValue(resolved_payload, @"defaultPromptText", default_prompt);
            if (accepted) {
              SetPayloadValue(resolved_payload, @"userInput", resolved_input);
            }
            [owner_ notifyRuntimeEventKind:@"javaScriptDialog" payload:resolved_payload];
            return;
          }

          alert.messageText = [NSString stringWithFormat:@"%@ prompt", AlertDisplayOrigin(origin)];
          NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 320, 24)];
          field.stringValue = default_prompt ?: @"";
          alert.accessoryView = field;
          [alert addButtonWithTitle:@"OK"];
          [alert addButtonWithTitle:@"Cancel"];
          BOOL accepted = RunAlert(alert, owner_) == NSAlertFirstButtonReturn;
          NSString *resolved_input = accepted ? field.stringValue : default_prompt;
          retained_callback->Continue(accepted, CefString(resolved_input.UTF8String));
          NSMutableDictionary<NSString *, NSString *> *resolved_payload = [@{
            @"requestID": request.requestID,
            @"phase": @"resolved",
            @"dialogType": dialog_type_name,
            @"messageText": message,
            @"accepted": BoolString(accepted),
            @"originURL": origin ?: @"",
          } mutableCopy];
          SetPayloadValue(resolved_payload, @"defaultPromptText", default_prompt);
          if (accepted) {
            SetPayloadValue(resolved_payload, @"userInput", resolved_input);
          }
          [owner_ notifyRuntimeEventKind:@"javaScriptDialog" payload:resolved_payload];
          return;
        }
        default:
          retained_callback->Continue(false, CefString());
          return;
        }
      };
    }
  });
  if (request == nil) {
    return false;
  }

  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRuntimePromptExternalResolutionGraceSeconds * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        if (owner_ != nil) {
          [owner_ resumeRuntimePromptRequest:request];
        }
      });
  return true;
}

bool GhoDexCEFClient::OnBeforeUnloadDialog(CefRefPtr<CefBrowser> browser,
                                           const CefString &message_text,
                                           bool is_reload,
                                           CefRefPtr<CefJSDialogCallback> callback) {
  (void)browser;
  if (!owner_ || !callback.get()) {
    return false;
  }

  NSString *message = [NSString stringWithUTF8String:message_text.ToString().c_str() ?: ""];
  NSString *origin = browser.get() ? [NSString stringWithUTF8String:browser->GetMainFrame()->GetURL().ToString().c_str() ?: ""] : @"";
  __block GhoDexCEFRuntimePromptRequest *request = nil;
  RunOnMainThreadSync(^{
    request = [owner_ beginRuntimePromptKind:@"javaScriptDialog" payload:@{
      @"phase": @"requested",
      @"dialogType": @"beforeUnload",
      @"messageText": message,
      @"originURL": origin ?: @"",
      @"isReload": BoolString(is_reload),
    }];
  });
  if (request == nil) {
    return false;
  }

  dispatch_semaphore_wait(
      request.semaphore,
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRuntimePromptExternalResolutionGraceSeconds * NSEC_PER_SEC)));

  __block BOOL externally_resolved = NO;
  __block BOOL canceled = NO;
  __block NSDictionary<NSString *, NSString *> *resolution_payload = nil;
  RunOnMainThreadSync(^{
    resolution_payload = [owner_ finishRuntimePromptRequest:request
                                         externallyResolved:&externally_resolved
                                                   canceled:&canceled];
  });
  if (canceled) {
    callback->Continue(false, CefString());
    return true;
  }

  if (externally_resolved) {
    BOOL accepted = [resolution_payload[@"accepted"] isEqualToString:@"true"];
    callback->Continue(accepted, CefString());
    [owner_ notifyRuntimeEventKind:@"javaScriptDialog" payload:@{
      @"requestID": request.requestID,
      @"phase": @"resolved",
      @"dialogType": @"beforeUnload",
      @"messageText": message,
      @"originURL": origin ?: @"",
      @"isReload": BoolString(is_reload),
      @"accepted": BoolString(accepted),
    }];
    return true;
  }

  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = is_reload ? @"Reload this page?" : @"Leave this page?";
  alert.informativeText = message.length > 0 ? message : @"Changes you made may not be saved.";
  alert.alertStyle = NSAlertStyleWarning;
  [alert addButtonWithTitle:is_reload ? @"Reload" : @"Leave"];
  [alert addButtonWithTitle:@"Stay"];
  BOOL accepted = RunAlert(alert, owner_) == NSAlertFirstButtonReturn;
  callback->Continue(accepted, CefString());
  [owner_ notifyRuntimeEventKind:@"javaScriptDialog" payload:@{
    @"requestID": request.requestID,
    @"phase": @"resolved",
    @"dialogType": @"beforeUnload",
    @"messageText": message,
    @"originURL": origin ?: @"",
    @"isReload": BoolString(is_reload),
    @"accepted": BoolString(accepted),
  }];
  return true;
}

bool GhoDexCEFClient::OnRequestMediaAccessPermission(
    CefRefPtr<CefBrowser> browser,
    CefRefPtr<CefFrame> frame,
    const CefString &requesting_origin,
    uint32_t requested_permissions,
    CefRefPtr<CefMediaAccessCallback> callback) {
  (void)browser;
  (void)frame;
  if (!owner_ || !callback.get()) {
    return false;
  }

  NSString *origin = [NSString stringWithUTF8String:requesting_origin.ToString().c_str() ?: ""];
  NSString *permission_label = MediaPermissionDescription(requested_permissions);
  __block GhoDexCEFRuntimePromptRequest *request = nil;
  RunOnMainThreadSync(^{
    request = [owner_ beginRuntimePromptKind:@"permissionRequest" payload:@{
      @"phase": @"requested",
      @"permissionKind": @"media",
      @"originURL": origin ?: @"",
      @"requestedPermissions": UInt32String(requested_permissions),
      @"requestedPermissionsLabel": permission_label,
    }];
  });
  if (request == nil) {
    return false;
  }

  dispatch_semaphore_wait(
      request.semaphore,
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRuntimePromptExternalResolutionGraceSeconds * NSEC_PER_SEC)));

  __block BOOL externally_resolved = NO;
  __block BOOL canceled = NO;
  __block NSDictionary<NSString *, NSString *> *resolution_payload = nil;
  RunOnMainThreadSync(^{
    resolution_payload = [owner_ finishRuntimePromptRequest:request
                                         externallyResolved:&externally_resolved
                                                   canceled:&canceled];
  });
  if (canceled) {
    callback->Cancel();
    return true;
  }

  if (externally_resolved) {
    NSString *result = resolution_payload[@"result"] ?: @"deny";
    if ([result isEqualToString:@"allow"]) {
      callback->Continue(requested_permissions);
    } else {
      callback->Cancel();
      result = [result isEqualToString:@"dismiss"] ? @"dismiss" : @"deny";
    }
    [owner_ notifyRuntimeEventKind:@"permissionRequest" payload:@{
      @"requestID": request.requestID,
      @"phase": @"resolved",
      @"permissionKind": @"media",
      @"originURL": origin ?: @"",
      @"requestedPermissions": UInt32String(requested_permissions),
      @"requestedPermissionsLabel": permission_label,
      @"result": result,
    }];
    return true;
  }

  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = [NSString stringWithFormat:@"%@ wants to use %@", AlertDisplayOrigin(origin), permission_label];
  alert.informativeText = @"Allow this browser page to access the requested device capabilities?";
  alert.alertStyle = NSAlertStyleInformational;
  [alert addButtonWithTitle:@"Allow"];
  [alert addButtonWithTitle:@"Block"];
  BOOL accepted = RunAlert(alert, owner_) == NSAlertFirstButtonReturn;
  if (accepted) {
    callback->Continue(requested_permissions);
  } else {
    callback->Cancel();
  }
  [owner_ notifyRuntimeEventKind:@"permissionRequest" payload:@{
    @"requestID": request.requestID,
    @"phase": @"resolved",
    @"permissionKind": @"media",
    @"originURL": origin ?: @"",
    @"requestedPermissions": UInt32String(requested_permissions),
    @"requestedPermissionsLabel": permission_label,
    @"result": accepted ? @"allow" : @"deny",
  }];
  return true;
}

bool GhoDexCEFClient::OnShowPermissionPrompt(CefRefPtr<CefBrowser> browser,
                                             uint64_t prompt_id,
                                             const CefString &requesting_origin,
                                             uint32_t requested_permissions,
                                             CefRefPtr<CefPermissionPromptCallback> callback) {
  (void)browser;
  (void)prompt_id;
  if (!owner_ || !callback.get()) {
    return false;
  }

  NSString *origin = [NSString stringWithUTF8String:requesting_origin.ToString().c_str() ?: ""];
  NSString *permission_label = PermissionPromptDescription(requested_permissions);
  __block GhoDexCEFRuntimePromptRequest *request = nil;
  RunOnMainThreadSync(^{
    request = [owner_ beginRuntimePromptKind:@"permissionRequest" payload:@{
      @"phase": @"requested",
      @"permissionKind": @"generic",
      @"originURL": origin ?: @"",
      @"requestedPermissions": UInt32String(requested_permissions),
      @"requestedPermissionsLabel": permission_label,
      @"promptID": UInt64String(prompt_id),
    }];
  });
  if (request == nil) {
    return false;
  }

  dispatch_semaphore_wait(
      request.semaphore,
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRuntimePromptExternalResolutionGraceSeconds * NSEC_PER_SEC)));

  __block BOOL externally_resolved = NO;
  __block BOOL canceled = NO;
  __block NSDictionary<NSString *, NSString *> *resolution_payload = nil;
  RunOnMainThreadSync(^{
    resolution_payload = [owner_ finishRuntimePromptRequest:request
                                         externallyResolved:&externally_resolved
                                                   canceled:&canceled];
  });
  if (canceled) {
    callback->Continue(CEF_PERMISSION_RESULT_DISMISS);
    return true;
  }

  if (externally_resolved) {
    NSString *result = resolution_payload[@"result"] ?: @"dismiss";
    if ([result isEqualToString:@"allow"]) {
      callback->Continue(CEF_PERMISSION_RESULT_ACCEPT);
    } else if ([result isEqualToString:@"deny"]) {
      callback->Continue(CEF_PERMISSION_RESULT_DENY);
    } else {
      result = @"dismiss";
      callback->Continue(CEF_PERMISSION_RESULT_DISMISS);
    }
    [owner_ notifyRuntimeEventKind:@"permissionRequest" payload:@{
      @"requestID": request.requestID,
      @"phase": @"resolved",
      @"permissionKind": @"generic",
      @"originURL": origin ?: @"",
      @"requestedPermissions": UInt32String(requested_permissions),
      @"requestedPermissionsLabel": permission_label,
      @"promptID": UInt64String(prompt_id),
      @"result": result,
    }];
    return true;
  }

  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = [NSString stringWithFormat:@"%@ wants %@", AlertDisplayOrigin(origin), permission_label];
  alert.informativeText = @"Choose whether to allow this permission request.";
  alert.alertStyle = NSAlertStyleInformational;
  [alert addButtonWithTitle:@"Allow"];
  [alert addButtonWithTitle:@"Block"];
  [alert addButtonWithTitle:@"Not Now"];

  NSModalResponse response = RunAlert(alert, owner_);
  NSString *result = @"dismiss";
  if (response == NSAlertFirstButtonReturn) {
    result = @"allow";
    callback->Continue(CEF_PERMISSION_RESULT_ACCEPT);
  } else if (response == NSAlertSecondButtonReturn) {
    result = @"deny";
    callback->Continue(CEF_PERMISSION_RESULT_DENY);
  } else {
    callback->Continue(CEF_PERMISSION_RESULT_DISMISS);
  }
  [owner_ notifyRuntimeEventKind:@"permissionRequest" payload:@{
    @"requestID": request.requestID,
    @"phase": @"resolved",
    @"permissionKind": @"generic",
    @"originURL": origin ?: @"",
    @"requestedPermissions": UInt32String(requested_permissions),
    @"requestedPermissionsLabel": permission_label,
    @"promptID": UInt64String(prompt_id),
    @"result": result,
  }];
  return true;
}

bool GhoDexCEFClient::GetAuthCredentials(CefRefPtr<CefBrowser> browser,
                                         const CefString &origin_url,
                                         bool isProxy,
                                         const CefString &host,
                                         int port,
                                         const CefString &realm,
                                         const CefString &scheme,
                                         CefRefPtr<CefAuthCallback> callback) {
  (void)browser;
  if (!owner_ || !callback.get()) {
    return false;
  }

  GhoDexCEFView *owner = owner_;
  NSString *origin = [NSString stringWithUTF8String:origin_url.ToString().c_str() ?: ""];
  NSString *host_string = [NSString stringWithUTF8String:host.ToString().c_str() ?: ""];
  NSString *realm_string = [NSString stringWithUTF8String:realm.ToString().c_str() ?: ""];
  std::string scheme_value = scheme.ToString();
  const char *scheme_cstr = scheme_value.c_str();
  NSString *scheme_string = (scheme_cstr != nullptr && scheme_cstr[0] != '\0')
      ? [NSString stringWithUTF8String:scheme_cstr]
      : @"authentication";
  __block GhoDexCEFRuntimePromptRequest *request = nil;
  RunOnMainThreadSync(^{
    request = [owner_ beginRuntimePromptKind:@"authenticationRequest" payload:@{
      @"phase": @"requested",
      @"originURL": origin ?: @"",
      @"host": host_string ?: @"",
      @"port": IntegerString(port),
      @"realm": realm_string ?: @"",
      @"scheme": scheme_string ?: @"authentication",
      @"isProxy": BoolString(isProxy),
    }];
  });
  if (request == nil) {
    return false;
  }

  dispatch_semaphore_wait(
      request.semaphore,
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRuntimePromptExternalResolutionGraceSeconds * NSEC_PER_SEC)));

  __block BOOL externally_resolved = NO;
  __block BOOL canceled = NO;
  __block NSDictionary<NSString *, NSString *> *resolution_payload = nil;
  RunOnMainThreadSync(^{
    resolution_payload = [owner_ finishRuntimePromptRequest:request
                                         externallyResolved:&externally_resolved
                                                   canceled:&canceled];
  });
  if (canceled) {
    callback->Cancel();
    return true;
  }

  if (externally_resolved) {
    BOOL accepted = [resolution_payload[@"accepted"] isEqualToString:@"true"];
    if (accepted) {
      callback->Continue(
          CefString((resolution_payload[@"username"] ?: @"").UTF8String),
          CefString((resolution_payload[@"password"] ?: @"").UTF8String));
    } else {
      callback->Cancel();
    }
    [owner_ notifyRuntimeEventKind:@"authenticationRequest" payload:@{
      @"requestID": request.requestID,
      @"phase": @"resolved",
      @"originURL": origin ?: @"",
      @"host": host_string ?: @"",
      @"port": IntegerString(port),
      @"realm": realm_string ?: @"",
      @"scheme": scheme_string ?: @"authentication",
      @"isProxy": BoolString(isProxy),
      @"accepted": BoolString(accepted),
    }];
    return true;
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"%@ requires %@", host_string.length > 0 ? host_string : AlertDisplayOrigin(origin), scheme_string];
    alert.informativeText = realm_string.length > 0 ? realm_string : @"Enter your username and password.";
    alert.alertStyle = NSAlertStyleInformational;

    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 52)];
    NSTextField *username = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 28, 320, 24)];
    NSSecureTextField *password = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 320, 24)];
    username.placeholderString = @"Username";
    password.placeholderString = @"Password";
    [accessory addSubview:username];
    [accessory addSubview:password];
    alert.accessoryView = accessory;

    [alert addButtonWithTitle:@"Sign In"];
    [alert addButtonWithTitle:@"Cancel"];
    BOOL accepted = RunAlert(alert, owner) == NSAlertFirstButtonReturn;
    if (accepted) {
      callback->Continue(CefString(username.stringValue.UTF8String),
                         CefString(password.stringValue.UTF8String));
    } else {
      callback->Cancel();
    }
    [owner notifyRuntimeEventKind:@"authenticationRequest" payload:@{
      @"requestID": request.requestID,
      @"phase": @"resolved",
      @"originURL": origin ?: @"",
      @"host": host_string ?: @"",
      @"port": IntegerString(port),
      @"realm": realm_string ?: @"",
      @"scheme": scheme_string ?: @"authentication",
      @"isProxy": BoolString(isProxy),
      @"accepted": BoolString(accepted),
    }];
  });
  return true;
}

bool GhoDexCEFClient::OnCertificateError(CefRefPtr<CefBrowser> browser,
                                         cef_errorcode_t cert_error,
                                         const CefString &request_url,
                                         CefRefPtr<CefSSLInfo> ssl_info,
                                         CefRefPtr<CefCallback> callback) {
  (void)browser;
  (void)ssl_info;
  if (!owner_ || !callback.get()) {
    return false;
  }

  NSString *url = [NSString stringWithUTF8String:request_url.ToString().c_str() ?: ""];
  NSString *error_code = IntegerString(static_cast<NSInteger>(cert_error));
  __block GhoDexCEFRuntimePromptRequest *request = nil;
  RunOnMainThreadSync(^{
    request = [owner_ beginRuntimePromptKind:@"certificateWarning" payload:@{
      @"phase": @"requested",
      @"requestURL": url ?: @"",
      @"errorCode": error_code,
    }];
  });
  if (request == nil) {
    return false;
  }

  dispatch_semaphore_wait(
      request.semaphore,
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRuntimePromptExternalResolutionGraceSeconds * NSEC_PER_SEC)));

  __block BOOL externally_resolved = NO;
  __block BOOL canceled = NO;
  __block NSDictionary<NSString *, NSString *> *resolution_payload = nil;
  RunOnMainThreadSync(^{
    resolution_payload = [owner_ finishRuntimePromptRequest:request
                                         externallyResolved:&externally_resolved
                                                   canceled:&canceled];
  });
  if (canceled) {
    callback->Cancel();
    return true;
  }

  if (externally_resolved) {
    BOOL accepted = [resolution_payload[@"accepted"] isEqualToString:@"true"];
    if (accepted) {
      callback->Continue();
    } else {
      callback->Cancel();
    }
    [owner_ notifyRuntimeEventKind:@"certificateWarning" payload:@{
      @"requestID": request.requestID,
      @"phase": @"resolved",
      @"requestURL": url ?: @"",
      @"errorCode": error_code,
      @"accepted": BoolString(accepted),
    }];
    return true;
  }

  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Certificate validation failed";
  alert.informativeText = [NSString stringWithFormat:
      @"The TLS certificate for %@ could not be verified (error %d). Continue anyway?",
      url.length > 0 ? url : @"this site",
      static_cast<int>(cert_error)];
  alert.alertStyle = NSAlertStyleWarning;
  [alert addButtonWithTitle:@"Continue"];
  [alert addButtonWithTitle:@"Cancel"];
  BOOL accepted = RunAlert(alert, owner_) == NSAlertFirstButtonReturn;
  if (accepted) {
    callback->Continue();
  } else {
    callback->Cancel();
  }
  [owner_ notifyRuntimeEventKind:@"certificateWarning" payload:@{
    @"requestID": request.requestID,
    @"phase": @"resolved",
    @"requestURL": url ?: @"",
    @"errorCode": error_code,
    @"accepted": BoolString(accepted),
  }];
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

  NSLog(@"[CEF] OnBeforePopup disposition=%d target=%s user_gesture=%d",
        static_cast<int>(target_disposition),
        target_url.ToString().c_str(),
        user_gesture ? 1 : 0);

  if (target_disposition == CEF_WOD_NEW_POPUP || target_disposition == CEF_WOD_NEW_WINDOW) {
    __block GhoDexCEFPopupWindowController *popup_controller = nil;
    RunOnMainThreadSync(^{
      popup_controller = [[GhoDexCEFPopupWindowController alloc] initWithSourceView:owner_
                                                                      popupFeatures:popupFeatures];
      [popup_controller presentPopupWindow];
    });

    GhoDexCEFView *popup_view = popup_controller.cefView;
    if (popup_view != nil) {
      client = [popup_view preparePopupHostingClient];
      if (client.get()) {
        CefRect bounds(0,
                       0,
                       static_cast<int>(popup_view.bounds.size.width),
                       static_cast<int>(popup_view.bounds.size.height));
        windowInfo.SetAsChild((__bridge CefWindowHandle)popup_view, bounds);
        NSLog(@"[CEF] Hosting real popup disposition=%d in dedicated popup window",
              static_cast<int>(target_disposition));
        std::string hosted_url = target_url.ToString();
        if (hosted_url.empty()) {
          hosted_url = "about:blank";
        }
        dispatch_async(dispatch_get_main_queue(), ^{
          [owner_ notifyHostedPopupWindowForURL:[NSString stringWithUTF8String:hosted_url.c_str() ?: "about:blank"]
                                    disposition:static_cast<NSInteger>(target_disposition)
                                    userGesture:user_gesture];
        });
        return false;
      }
      NSLog(@"[CEF] Popup host client preparation failed for disposition=%d",
            static_cast<int>(target_disposition));
    } else {
      NSLog(@"[CEF] Popup host view was unavailable for disposition=%d",
            static_cast<int>(target_disposition));
    }
  }

  std::string requested_url = target_url.ToString();
  if (requested_url.empty()) {
    requested_url = "about:blank";
  }

  NSString *url_string = [NSString stringWithUTF8String:requested_url.c_str() ?: "about:blank"];
  NSLog(@"[CEF] Popup requested disposition=%d url=%@", static_cast<int>(target_disposition), url_string);
  dispatch_async(dispatch_get_main_queue(), ^{
    [owner_ notifyOpenURLInNewTab:url_string ?: @"about:blank"
                     disposition:static_cast<NSInteger>(target_disposition)
                     userGesture:user_gesture];
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
  ExecuteJavaScript(script, nullptr);
}

void GhoDexCEFClient::ExecuteJavaScript(const std::string &script,
                                        const std::string *frame_name) {
  CEF_REQUIRE_UI_THREAD();
  if (!browser_) {
    return;
  }

  CefRefPtr<CefFrame> frame = ResolveFrame(frame_name, nullptr);
  if (frame) {
    frame->ExecuteJavaScript(script, frame->GetURL(), 0);
  }
}

bool GhoDexCEFClient::EvaluateJavaScript(const std::string &script,
                                         const std::string *frame_name,
                                         const std::string &request_id,
                                         std::string *error_description) {
  CEF_REQUIRE_UI_THREAD();
  if (!browser_) {
    if (error_description != nullptr) {
      *error_description = "The CEF browser instance is not ready.";
    }
    return false;
  }

  CefRefPtr<CefFrame> frame = ResolveFrame(frame_name, error_description);
  if (!frame.get()) {
    return false;
  }

  CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create(kEvaluateRequestMessageName);
  CefRefPtr<CefListValue> arguments = message->GetArgumentList();
  arguments->SetString(kEvaluateRequestIDIndex, request_id);
  arguments->SetString(kEvaluateScriptIndex, script);
  frame->SendProcessMessage(PID_RENDERER, message);
  return true;
}

bool GhoDexCEFClient::ListFrames(std::string *result_json,
                                 std::string *error_description) {
  CEF_REQUIRE_UI_THREAD();
  if (!browser_) {
    if (error_description != nullptr) {
      *error_description = "The CEF browser instance is not ready.";
    }
    return false;
  }

  CefRefPtr<CefFrame> main_frame = browser_->GetMainFrame();
  if (!main_frame.get()) {
    if (error_description != nullptr) {
      *error_description = "The CEF main frame is unavailable.";
    }
    return false;
  }

  NSMutableArray<NSDictionary *> *frames = [NSMutableArray array];
  NSMutableSet<NSString *> *seen_frame_ids = [NSMutableSet set];

  auto append_frame = ^(CefRefPtr<CefFrame> frame) {
    if (!frame.get()) {
      return;
    }

    NSString *frame_id = [NSString stringWithUTF8String:frame->GetIdentifier().ToString().c_str() ?: ""];
    if (frame_id == nil || [seen_frame_ids containsObject:frame_id]) {
      return;
    }
    [seen_frame_ids addObject:frame_id];

    NSString *name = [NSString stringWithUTF8String:frame->GetName().ToString().c_str() ?: ""];
    NSString *url = [NSString stringWithUTF8String:frame->GetURL().ToString().c_str() ?: ""];
    BOOL is_main = main_frame.get() && frame->GetIdentifier() == main_frame->GetIdentifier();
    [frames addObject:@{
      @"name" : name ?: @"",
      @"url" : url ?: @"",
      @"isMainFrame" : @(is_main),
    }];
  };

  append_frame(main_frame);

  std::vector<CefString> frame_identifiers;
  browser_->GetFrameIdentifiers(frame_identifiers);
  for (const auto &frame_identifier : frame_identifiers) {
    CefRefPtr<CefFrame> frame = browser_->GetFrameByIdentifier(frame_identifier);
    append_frame(frame);
  }

  NSError *serialization_error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:frames options:0 error:&serialization_error];
  if (!data || serialization_error != nil) {
    if (error_description != nullptr) {
      NSString *message = serialization_error.localizedDescription ?: @"The browser frame list could not be encoded as JSON.";
      *error_description = std::string(message.UTF8String ?: "The browser frame list could not be encoded as JSON.");
    }
    return false;
  }

  NSString *encoded = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (encoded.length == 0) {
    if (error_description != nullptr) {
      *error_description = "The browser frame list could not be encoded as UTF-8.";
    }
    return false;
  }

  if (result_json != nullptr) {
    *result_json = std::string(encoded.UTF8String ?: "[]");
  }
  return true;
}

CefRefPtr<CefFrame> GhoDexCEFClient::ResolveFrame(const std::string *frame_name,
                                                  std::string *error_description) {
  CEF_REQUIRE_UI_THREAD();
  if (!browser_) {
    if (error_description != nullptr) {
      *error_description = "The CEF browser instance is not ready.";
    }
    return nullptr;
  }

  if (frame_name == nullptr || frame_name->empty()) {
    CefRefPtr<CefFrame> frame = browser_->GetMainFrame();
    if (!frame.get() && error_description != nullptr) {
      *error_description = "The CEF main frame is unavailable.";
    }
    return frame;
  }

  CefRefPtr<CefFrame> frame = browser_->GetFrameByName(*frame_name);
  if (!frame.get() && error_description != nullptr) {
    *error_description = "The requested CEF frame is unavailable.";
  }
  return frame;
}

void GhoDexCEFClient::WasResized() {
  CEF_REQUIRE_UI_THREAD();
  if (browser_) {
    browser_->GetHost()->WasResized();
  }
}

bool GhoDexCEFClient::SendTrustedClick(double x,
                                       double y,
                                       std::string *error_description) {
  CEF_REQUIRE_UI_THREAD();
  if (!browser_) {
    if (error_description) {
      *error_description = "The browser is unavailable for trusted click injection.";
    }
    return false;
  }

  CefRefPtr<CefBrowserHost> host = browser_->GetHost();
  if (!host.get()) {
    if (error_description) {
      *error_description = "The browser host is unavailable for trusted click injection.";
    }
    return false;
  }

  const int view_width = owner_ ? static_cast<int>(owner_.bounds.size.width) : 0;
  const int view_height = owner_ ? static_cast<int>(owner_.bounds.size.height) : 0;
  const int event_x = std::max(0, static_cast<int>(std::lround(x)));
  const int event_y = std::max(0, static_cast<int>(std::lround(y)));
  if ((view_width > 0 && event_x >= view_width) || (view_height > 0 && event_y >= view_height)) {
    if (error_description) {
      *error_description = "The trusted click target is outside the current browser view bounds.";
    }
    return false;
  }

  host->SetFocus(true);

  CefMouseEvent move_event;
  move_event.x = event_x;
  move_event.y = event_y;
  move_event.modifiers = 0;
  host->SendMouseMoveEvent(move_event, false);

  CefMouseEvent down_event = move_event;
  down_event.modifiers = EVENTFLAG_LEFT_MOUSE_BUTTON;
  host->SendMouseClickEvent(down_event, MBT_LEFT, false, 1);

  CefMouseEvent up_event = move_event;
  up_event.modifiers = 0;
  host->SendMouseClickEvent(up_event, MBT_LEFT, true, 1);
  return true;
}

void GhoDexCEFClient::CloseBrowser() {
  CEF_REQUIRE_UI_THREAD();
  if (browser_) {
    pending_download_callbacks_.clear();
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

NSString *ConfiguredAppSupportRootPath(void) {
  NSString *override_path = NSProcessInfo.processInfo.environment[@"GHODEX_BROWSER_APP_SUPPORT_ROOT"];
  NSString *validated_override = ValidatedDirectoryPath(override_path);
  if (validated_override.length > 0) {
    return validated_override;
  }

  NSURL *base =
      [NSFileManager.defaultManager.homeDirectoryForCurrentUser
          URLByAppendingPathComponent:@"Library"
                         isDirectory:YES];
  base = [base URLByAppendingPathComponent:@"Application Support" isDirectory:YES];
  base = [base URLByAppendingPathComponent:@"GhoDex" isDirectory:YES];
  return base.path;
}

NSString *ConfiguredCEFRootPath(void) {
  return [ConfiguredAppSupportRootPath() stringByAppendingPathComponent:@"CEF"];
}

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

  return [ConfiguredCEFRootPath() stringByAppendingPathComponent:@"current"];
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

int ConfiguredRemoteDebuggingPort(void) {
  if (HasIsolatedAppSupportRootOverride()) {
    return 0;
  }

  NSInteger defaults_port =
      [NSUserDefaults.standardUserDefaults integerForKey:@"BrowserCEFRemoteDebugPort"];
  if (defaults_port >= 1 && defaults_port <= 65535) {
    return static_cast<int>(defaults_port);
  }

  return 0;
}

void ApplyRemoteDebuggingCommandLinePolicy(
    const CefString &process_type,
    CefRefPtr<CefCommandLine> command_line) {
  if (!command_line.get()) {
    return;
  }

  std::string process_type_value = process_type.ToString();
  NSString *process_label = process_type_value.empty()
      ? @"browser"
      : [NSString stringWithUTF8String:process_type_value.c_str() ?: "unknown"];

  int configured_port = ConfiguredRemoteDebuggingPort();
  bool has_remote_port = command_line->HasSwitch("remote-debugging-port");
  bool has_remote_pipe = command_line->HasSwitch("remote-debugging-pipe");
  bool has_remote_allow_origins = command_line->HasSwitch("remote-allow-origins");

  if (configured_port > 0) {
    std::string current_port_value =
        has_remote_port ? command_line->GetSwitchValue("remote-debugging-port").ToString() : "";
    NSString *current_port = [NSString stringWithUTF8String:current_port_value.c_str() ?: ""];
    NSString *desired_port = [NSString stringWithFormat:@"%d", configured_port];
    if (!has_remote_port || ![current_port isEqualToString:desired_port]) {
#if CEF_API_ADDED(14100)
      command_line->RemoveSwitch("remote-debugging-port");
#endif
      command_line->AppendSwitchWithValue("remote-debugging-port", desired_port.UTF8String);
      NSLog(@"[CEF] Applied remote-debugging-port=%@ to %@ process command line",
            desired_port,
            process_label);
    }
    return;
  }

  if (!has_remote_port && !has_remote_pipe && !has_remote_allow_origins) {
    return;
  }

#if CEF_API_ADDED(14100)
  command_line->RemoveSwitch("remote-debugging-port");
  command_line->RemoveSwitch("remote-debugging-pipe");
  command_line->RemoveSwitch("remote-allow-origins");
#endif
  NSLog(@"[CEF] Stripped unexpected remote debugging switches from %@ process command line",
        process_label);
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
  NSString *app_support_root = ConfiguredAppSupportRootPath();
  if (app_support_root.length == 0) {
    return nil;
  }

  NSURL *base = [[NSURL fileURLWithPath:app_support_root isDirectory:YES] URLByDeletingLastPathComponent];
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

BOOL HasIsolatedAppSupportRootOverride(void) {
  NSString *override_path = NSProcessInfo.processInfo.environment[@"GHODEX_BROWSER_APP_SUPPORT_ROOT"];
  return ValidatedDirectoryPath(override_path).length > 0;
}

NSString *ConfiguredExternalProfilePath(void) {
  NSString *override_path = NSProcessInfo.processInfo.environment[@"GHODEX_CEF_PROFILE_PATH"];
  NSString *validated = ValidatedDirectoryPath(override_path);
  if (validated.length > 0) {
    return validated;
  }

  if (HasIsolatedAppSupportRootOverride()) {
    return nil;
  }

  NSString *defaults_path =
      [NSUserDefaults.standardUserDefaults stringForKey:@"BrowserCEFProfilePath"];
  return ValidatedDirectoryPath(defaults_path);
}

NSString *ExternalProfileSourceUserDataDir(NSString *external_profile) {
  if (external_profile.length == 0) {
    return nil;
  }

  NSString *user_data_dir = external_profile.stringByDeletingLastPathComponent;
  return user_data_dir.length > 0 ? user_data_dir : nil;
}

NSString *ExternalProfileRuntimeStatePath(NSString *runtime_root) {
  if (runtime_root.length == 0) {
    return nil;
  }

  return [runtime_root stringByAppendingPathComponent:@".ghodex-external-profile-state.plist"];
}

NSDictionary *ExternalProfileRuntimeState(NSString *runtime_root) {
  NSString *state_path = ExternalProfileRuntimeStatePath(runtime_root);
  if (state_path.length == 0) {
    return @{};
  }

  NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:state_path];
  return [state isKindOfClass:NSDictionary.class] ? state : @{};
}

BOOL WriteExternalProfileRuntimeState(NSString *runtime_root, NSDictionary *state) {
  NSString *state_path = ExternalProfileRuntimeStatePath(runtime_root);
  if (state_path.length == 0) {
    return NO;
  }

  return [state writeToFile:state_path atomically:YES];
}

BOOL HasOsCryptPrefix(NSData *value) {
  if (value.length < 4) {
    return NO;
  }

  const unsigned char *bytes = static_cast<const unsigned char *>(value.bytes);
  return bytes[0] == 'v' && bytes[1] == '1' && bytes[2] == '0';
}

NSData * _Nullable CopyKeychainSecret(NSString *service, NSString *account) {
  if (service.length == 0 || account.length == 0) {
    return nil;
  }

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/usr/bin/security";
  task.arguments = @[ @"find-generic-password", @"-w", @"-s", service, @"-a", account ];
  NSPipe *stdout_pipe = [NSPipe pipe];
  NSPipe *stderr_pipe = [NSPipe pipe];
  task.standardOutput = stdout_pipe;
  task.standardError = stderr_pipe;

  @try {
    [task launch];
  } @catch (NSException *exception) {
    return nil;
  }

  [task waitUntilExit];
  if (task.terminationStatus != 0) {
    return nil;
  }

  NSData *output = [stdout_pipe.fileHandleForReading readDataToEndOfFile];
  NSString *secret_string = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
  secret_string = [secret_string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  return [secret_string dataUsingEncoding:NSUTF8StringEncoding];
}

NSData * _Nullable DerivedSafeStorageKey(NSData *secret) {
  if (secret.length == 0) {
    return nil;
  }

  const char salt[] = "saltysalt";
  NSMutableData *derived = [NSMutableData dataWithLength:kCCKeySizeAES128];
  int status = CCKeyDerivationPBKDF(kCCPBKDF2,
                                   static_cast<const char *>(secret.bytes),
                                   secret.length,
                                   reinterpret_cast<const uint8_t *>(salt),
                                   strlen(salt),
                                   kCCPRFHmacAlgSHA1,
                                   1003,
                                   static_cast<uint8_t *>(derived.mutableBytes),
                                   derived.length);
  return status == kCCSuccess ? derived : nil;
}

NSData *MockSafeStorageSecret(void) {
  // Chromium's `--use-mock-keychain` path derives the runtime encryption key
  // from the mock password returned by MockAppleKeychain/MockKeychain.
  return [@"mock_password" dataUsingEncoding:NSUTF8StringEncoding];
}

NSData * _Nullable AESCBCCryptRaw(NSData *input, NSData *key, CCOperation operation) {
  if (input.length == 0 || key.length != kCCKeySizeAES128) {
    return nil;
  }

  char iv[kCCBlockSizeAES128];
  memset(iv, ' ', sizeof(iv));

  size_t output_capacity = input.length + kCCBlockSizeAES128;
  NSMutableData *output = [NSMutableData dataWithLength:output_capacity];
  size_t output_length = 0;
  CCCryptorStatus status = CCCrypt(operation,
                                   kCCAlgorithmAES,
                                   0,
                                   key.bytes,
                                   key.length,
                                   iv,
                                   input.bytes,
                                   input.length,
                                   output.mutableBytes,
                                   output.length,
                                   &output_length);
  if (status != kCCSuccess) {
    return nil;
  }

  output.length = output_length;
  return output;
}

NSData * _Nullable DecryptOsCryptValue(NSData *encrypted_value, NSData *key) {
  if (!HasOsCryptPrefix(encrypted_value) || key.length == 0) {
    return nil;
  }

  NSData *ciphertext = [encrypted_value subdataWithRange:NSMakeRange(3, encrypted_value.length - 3)];
  NSData *padded_plaintext = AESCBCCryptRaw(ciphertext, key, kCCDecrypt);
  if (padded_plaintext.length == 0) {
    return nil;
  }

  const uint8_t *bytes = static_cast<const uint8_t *>(padded_plaintext.bytes);
  uint8_t pad_length = bytes[padded_plaintext.length - 1];
  if (pad_length == 0 || pad_length > kCCBlockSizeAES128 || pad_length > padded_plaintext.length) {
    return nil;
  }

  for (NSUInteger index = padded_plaintext.length - pad_length; index < padded_plaintext.length; index++) {
    if (bytes[index] != pad_length) {
      return nil;
    }
  }

  return [padded_plaintext subdataWithRange:NSMakeRange(0, padded_plaintext.length - pad_length)];
}

NSData * _Nullable EncryptOsCryptValue(NSData *plaintext, NSData *key) {
  if (plaintext.length == 0 || key.length == 0) {
    return nil;
  }

  uint8_t pad_length = kCCBlockSizeAES128 - (plaintext.length % kCCBlockSizeAES128);
  if (pad_length == 0) {
    pad_length = kCCBlockSizeAES128;
  }

  NSMutableData *padded_plaintext = [plaintext mutableCopy];
  uint8_t padding[kCCBlockSizeAES128];
  memset(padding, pad_length, sizeof(padding));
  [padded_plaintext appendBytes:padding length:pad_length];

  NSData *ciphertext = AESCBCCryptRaw(padded_plaintext, key, kCCEncrypt);
  if (ciphertext.length == 0) {
    return nil;
  }

  NSMutableData *wrapped = [NSMutableData dataWithBytes:"v10" length:3];
  [wrapped appendData:ciphertext];
  return wrapped;
}

struct ExternalProfileCryptoContext {
  NSData *chromeKey = nil;
  NSData *chromiumKey = nil;
};

ExternalProfileCryptoContext LoadExternalProfileCryptoContext(void) {
  ExternalProfileCryptoContext context;
  context.chromeKey = DerivedSafeStorageKey(CopyKeychainSecret(@"Chrome Safe Storage", @"Chrome"));
  context.chromiumKey = DerivedSafeStorageKey(MockSafeStorageSecret());
  return context;
}

struct ExternalProfileMigrationStats {
  NSUInteger cookiesRewrapped = 0;
  NSUInteger tokenServiceRewrapped = 0;
  NSUInteger loginPasswordsRewrapped = 0;
  NSUInteger skippedAlreadyChromium = 0;
  NSUInteger skippedUnknown = 0;
};

BOOL OpenSQLiteDatabase(NSString *path, sqlite3 **db, NSString **error_message) {
  int status = sqlite3_open_v2(path.fileSystemRepresentation,
                               db,
                               SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                               nullptr);
  if (status != SQLITE_OK || *db == nullptr) {
    if (error_message != nullptr) {
      *error_message = [NSString stringWithFormat:@"Failed to open %@: %s",
                                                  path,
                                                  *db != nullptr ? sqlite3_errmsg(*db) : sqlite3_errstr(status)];
    }
    if (*db != nullptr) {
      sqlite3_close(*db);
      *db = nullptr;
    }
    return NO;
  }

  sqlite3_busy_timeout(*db, 5000);
  return YES;
}

BOOL SQLiteExec(sqlite3 *db, const char *sql, NSString **error_message) {
  char *raw_error = nullptr;
  int status = sqlite3_exec(db, sql, nullptr, nullptr, &raw_error);
  if (status == SQLITE_OK) {
    return YES;
  }

  if (error_message != nullptr) {
    NSString *message =
        [NSString stringWithFormat:@"SQLite error %d: %s", status, raw_error != nullptr ? raw_error : sqlite3_errmsg(db)];
    *error_message = message;
  }
  if (raw_error != nullptr) {
    sqlite3_free(raw_error);
  }
  return NO;
}

NSData *SQLiteBlobColumn(sqlite3_stmt *statement, int column) {
  const void *bytes = sqlite3_column_blob(statement, column);
  int length = sqlite3_column_bytes(statement, column);
  if (bytes == nullptr || length <= 0) {
    return nil;
  }
  return [NSData dataWithBytes:bytes length:(NSUInteger)length];
}

BOOL RewrapEncryptedRows(sqlite3 *db,
                         const char *select_sql,
                         const char *update_sql,
                         BOOL bind_rowid,
                         NSData *source_key,
                         NSData *target_key,
                         NSUInteger *rewrapped_count,
                         NSUInteger *already_target_count,
                         NSUInteger *unknown_count,
                         NSString **error_message) {
  sqlite3_stmt *select_statement = nullptr;
  if (sqlite3_prepare_v2(db, select_sql, -1, &select_statement, nullptr) != SQLITE_OK) {
    if (error_message != nullptr) {
      *error_message = [NSString stringWithFormat:@"Failed to prepare select: %s", sqlite3_errmsg(db)];
    }
    return NO;
  }

  sqlite3_stmt *update_statement = nullptr;
  if (sqlite3_prepare_v2(db, update_sql, -1, &update_statement, nullptr) != SQLITE_OK) {
    sqlite3_finalize(select_statement);
    if (error_message != nullptr) {
      *error_message = [NSString stringWithFormat:@"Failed to prepare update: %s", sqlite3_errmsg(db)];
    }
    return NO;
  }

  while (sqlite3_step(select_statement) == SQLITE_ROW) {
    NSData *current_value = SQLiteBlobColumn(select_statement, 1);
    if (current_value.length == 0 || !HasOsCryptPrefix(current_value)) {
      continue;
    }

    if (target_key.length > 0) {
      NSData *target_plaintext = DecryptOsCryptValue(current_value, target_key);
      if (target_plaintext.length > 0) {
        if (already_target_count != nullptr) {
          *already_target_count += 1;
        }
        continue;
      }
    }

    NSData *source_plaintext = source_key.length > 0 ? DecryptOsCryptValue(current_value, source_key) : nil;
    if (source_plaintext.length == 0) {
      if (unknown_count != nullptr) {
        *unknown_count += 1;
      }
      continue;
    }

    NSData *rewrapped_value = EncryptOsCryptValue(source_plaintext, target_key);
    if (rewrapped_value.length == 0) {
      sqlite3_finalize(update_statement);
      sqlite3_finalize(select_statement);
      if (error_message != nullptr) {
        *error_message = @"Failed to re-encrypt an os_crypt value for the runtime profile.";
      }
      return NO;
    }

    sqlite3_reset(update_statement);
    sqlite3_clear_bindings(update_statement);
    sqlite3_bind_blob(update_statement,
                      1,
                      rewrapped_value.bytes,
                      (int)rewrapped_value.length,
                      SQLITE_TRANSIENT);
    if (bind_rowid) {
      sqlite3_bind_int64(update_statement, 2, sqlite3_column_int64(select_statement, 0));
    } else {
      const unsigned char *text = sqlite3_column_text(select_statement, 0);
      if (text == nullptr) {
        if (unknown_count != nullptr) {
          *unknown_count += 1;
        }
        continue;
      }
      sqlite3_bind_text(update_statement, 2, reinterpret_cast<const char *>(text), -1, SQLITE_TRANSIENT);
    }

    if (sqlite3_step(update_statement) != SQLITE_DONE) {
      sqlite3_finalize(update_statement);
      sqlite3_finalize(select_statement);
      if (error_message != nullptr) {
        *error_message = [NSString stringWithFormat:@"Failed to update runtime profile data: %s", sqlite3_errmsg(db)];
      }
      return NO;
    }

    if (rewrapped_count != nullptr) {
      *rewrapped_count += 1;
    }
  }

  sqlite3_finalize(update_statement);
  sqlite3_finalize(select_statement);
  return YES;
}

BOOL RewrapDatabaseAtPath(NSString *path,
                          const char *select_sql,
                          const char *update_sql,
                          BOOL bind_rowid,
                          NSData *source_key,
                          NSData *target_key,
                          NSUInteger *rewrapped_count,
                          NSUInteger *already_target_count,
                          NSUInteger *unknown_count,
                          NSString **error_message) {
  if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
    return YES;
  }

  sqlite3 *db = nullptr;
  if (!OpenSQLiteDatabase(path, &db, error_message)) {
    return NO;
  }

  BOOL ok = SQLiteExec(db, "BEGIN IMMEDIATE TRANSACTION", error_message) &&
            RewrapEncryptedRows(db,
                                select_sql,
                                update_sql,
                                bind_rowid,
                                source_key,
                                target_key,
                                rewrapped_count,
                                already_target_count,
                                unknown_count,
                                error_message);
  if (ok) {
    ok = SQLiteExec(db, "COMMIT TRANSACTION", error_message);
  } else {
    SQLiteExec(db, "ROLLBACK TRANSACTION", nullptr);
  }

  sqlite3_close(db);
  return ok;
}

BOOL RewrapRuntimeProfileData(NSString *runtime_profile_path,
                              const ExternalProfileCryptoContext &crypto_context,
                              ExternalProfileMigrationStats *stats,
                              NSString **error_message) {
  if (runtime_profile_path.length == 0 || crypto_context.chromiumKey.length == 0) {
    return YES;
  }

  BOOL ok =
      RewrapDatabaseAtPath([runtime_profile_path stringByAppendingPathComponent:@"Network/Cookies"],
                           "SELECT rowid, encrypted_value FROM cookies WHERE length(encrypted_value) > 3",
                           "UPDATE cookies SET encrypted_value = ? WHERE rowid = ?",
                           YES,
                           crypto_context.chromeKey,
                           crypto_context.chromiumKey,
                           &stats->cookiesRewrapped,
                           &stats->skippedAlreadyChromium,
                           &stats->skippedUnknown,
                           error_message) &&
      RewrapDatabaseAtPath([runtime_profile_path stringByAppendingPathComponent:@"Cookies"],
                           "SELECT rowid, encrypted_value FROM cookies WHERE length(encrypted_value) > 3",
                           "UPDATE cookies SET encrypted_value = ? WHERE rowid = ?",
                           YES,
                           crypto_context.chromeKey,
                           crypto_context.chromiumKey,
                           &stats->cookiesRewrapped,
                           &stats->skippedAlreadyChromium,
                           &stats->skippedUnknown,
                           error_message) &&
      RewrapDatabaseAtPath([runtime_profile_path stringByAppendingPathComponent:@"Login Data"],
                           "SELECT rowid, password_value FROM logins WHERE length(password_value) > 3",
                           "UPDATE logins SET password_value = ? WHERE rowid = ?",
                           YES,
                           crypto_context.chromeKey,
                           crypto_context.chromiumKey,
                           &stats->loginPasswordsRewrapped,
                           &stats->skippedAlreadyChromium,
                           &stats->skippedUnknown,
                           error_message) &&
      RewrapDatabaseAtPath([runtime_profile_path stringByAppendingPathComponent:@"Web Data"],
                           "SELECT service, encrypted_token FROM token_service WHERE length(encrypted_token) > 3",
                           "UPDATE token_service SET encrypted_token = ? WHERE service = ?",
                           NO,
                           crypto_context.chromeKey,
                           crypto_context.chromiumKey,
                           &stats->tokenServiceRewrapped,
                           &stats->skippedAlreadyChromium,
                           &stats->skippedUnknown,
                           error_message);
  return ok;
}

BOOL CopyChromeUserDataRoot(NSString *source_root,
                            NSString *target_root,
                            NSString *profile_directory,
                            BOOL overwrite_existing,
                            NSString **error_message) {
  NSFileManager *file_manager = NSFileManager.defaultManager;
  NSString *resolved_source_root = CanonicalCEFPath(source_root) ?: source_root.stringByStandardizingPath;
  NSError *directory_error = nil;
  [file_manager createDirectoryAtPath:target_root
          withIntermediateDirectories:YES
                           attributes:nil
                                error:&directory_error];
  if (directory_error != nil) {
    if (error_message != nullptr) {
      *error_message = [NSString stringWithFormat:@"Failed to create runtime profile root %@: %@",
                                                  target_root,
                                                  directory_error.localizedDescription];
    }
    return NO;
  }

  NSSet<NSString *> *excluded_exact_names =
      [NSSet setWithArray:@[ @"SingletonCookie", @"SingletonLock", @"SingletonSocket" ]];
  NSSet<NSString *> *excluded_directory_names = [NSSet
      setWithArray:@[ @"Crashpad",
                      @"Code Cache",
                      @"component_crx_cache",
                      @"DawnCache",
                      @"Extension Rules",
                      @"Extension Scripts",
                      @"Extension State",
                      @"Extensions",
                      @"GPUCache",
                      @"GrShaderCache",
                      @"GraphiteDawnCache",
                      @"ShaderCache" ]];
  NSSet<NSString *> *excluded_selected_profile_entries =
      [NSSet setWithArray:@[ @"Sync App Settings" ]];
  NSSet<NSString *> *allowed_top_level_names =
      [NSSet setWithArray:@[ profile_directory, @"Local State", @"Last Version", @"First Run" ]];
  // The staged mirror can stay broad, but the runtime seed should stay narrow:
  // copy the selected profile subtree in full, preserve only the minimum
  // Chrome-wide metadata needed beside it, and continue excluding ephemeral
  // crash/cache/lock state. Keep profile-owned auth/web-app state intact so
  // Chromium can reuse the mirrored Google session without Secure Preferences
  // / Web Data drift from hand-edited runtime sanitization.
  NSURL *source_root_url = [NSURL fileURLWithPath:resolved_source_root isDirectory:YES];
  NSString *source_root_prefix = [source_root_url.path stringByAppendingString:@"/"];
  NSDirectoryEnumerator<NSURL *> *enumerator =
      [file_manager enumeratorAtURL:source_root_url
          includingPropertiesForKeys:@[
            NSURLIsDirectoryKey,
            NSURLContentModificationDateKey,
            NSURLFileSizeKey,
            NSURLIsSymbolicLinkKey,
          ]
                             options:NSDirectoryEnumerationSkipsHiddenFiles
                        errorHandler:^BOOL(NSURL *url, NSError *error) {
                          NSLog(@"[CEF] Failed to enumerate %@ while seeding runtime profile: %@",
                                url.path,
                                error.localizedDescription);
                          return YES;
                        }];
  if (enumerator == nil) {
    return YES;
  }

  while (NSURL *source_url = enumerator.nextObject) {
    if (![source_url.path hasPrefix:source_root_prefix]) {
      continue;
    }
    NSString *relative_path =
        [source_url.path stringByReplacingOccurrencesOfString:source_root_prefix withString:@""];
    NSString *name = source_url.lastPathComponent;
    NSArray<NSString *> *path_components = relative_path.pathComponents;
    NSString *top_level_name = path_components.firstObject;
    NSDictionary<NSURLResourceKey, id> *values =
        [source_url resourceValuesForKeys:@[
          NSURLIsDirectoryKey,
          NSURLContentModificationDateKey,
          NSURLFileSizeKey,
          NSURLIsSymbolicLinkKey,
        ]
                                    error:nil];
    BOOL is_directory = [values[NSURLIsDirectoryKey] boolValue];
    BOOL is_symbolic_link = [values[NSURLIsSymbolicLinkKey] boolValue];

    if (top_level_name.length == 0) {
      if (is_directory) {
        [enumerator skipDescendants];
      }
      continue;
    }

    if (path_components.count == 1) {
      BOOL is_selected_profile_root = [top_level_name isEqualToString:profile_directory];
      BOOL is_other_profile_root =
          ([top_level_name hasPrefix:@"Profile "] ||
           [top_level_name isEqualToString:@"Default"] ||
           [top_level_name isEqualToString:@"Guest Profile"] ||
           [top_level_name isEqualToString:@"System Profile"]) &&
          !is_selected_profile_root;
      if (is_other_profile_root) {
        if (is_directory) {
          [enumerator skipDescendants];
        }
        continue;
      }

      if (!is_selected_profile_root && ![allowed_top_level_names containsObject:top_level_name]) {
        if (is_directory) {
          [enumerator skipDescendants];
        }
        continue;
      }
    }

    if ([excluded_exact_names containsObject:name]) {
      if (is_directory) {
        [enumerator skipDescendants];
      }
      continue;
    }

    if ([top_level_name isEqualToString:profile_directory] &&
        [excluded_selected_profile_entries containsObject:name]) {
      if (is_directory) {
        [enumerator skipDescendants];
      }
      continue;
    }

    if (is_directory && [excluded_directory_names containsObject:name]) {
      [enumerator skipDescendants];
      continue;
    }

    NSString *target_path = [target_root stringByAppendingPathComponent:relative_path];
    if (is_directory) {
      NSError *create_error = nil;
      [file_manager createDirectoryAtPath:target_path
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&create_error];
      if (create_error != nil) {
        if (error_message != nullptr) {
          *error_message = [NSString stringWithFormat:@"Failed to create %@: %@",
                                                      target_path,
                                                      create_error.localizedDescription];
        }
        return NO;
      }
      continue;
    }

    if (is_symbolic_link) {
      NSError *remove_error = nil;
      if ([file_manager fileExistsAtPath:target_path]) {
        [file_manager removeItemAtPath:target_path error:&remove_error];
      }
      if (remove_error != nil) {
        if (error_message != nullptr) {
          *error_message = [NSString stringWithFormat:@"Failed to replace symlink %@: %@",
                                                      target_path,
                                                      remove_error.localizedDescription];
        }
        return NO;
      }
      NSString *destination = [file_manager destinationOfSymbolicLinkAtPath:source_url.path error:nil];
      NSError *link_error = nil;
      [file_manager createSymbolicLinkAtPath:target_path
                    withDestinationPath:destination ?: @""
                                  error:&link_error];
      if (link_error != nil) {
        if (error_message != nullptr) {
          *error_message = [NSString stringWithFormat:@"Failed to copy symlink %@: %@",
                                                      source_url.path,
                                                      link_error.localizedDescription];
        }
        return NO;
      }
      continue;
    }

    BOOL should_copy = ![file_manager fileExistsAtPath:target_path];
    if (!should_copy && overwrite_existing) {
      NSDictionary<NSFileAttributeKey, id> *source_attributes =
          [file_manager attributesOfItemAtPath:source_url.path error:nil];
      NSDictionary<NSFileAttributeKey, id> *target_attributes =
          [file_manager attributesOfItemAtPath:target_path error:nil];
      should_copy =
          ![source_attributes[NSFileSize] isEqual:target_attributes[NSFileSize]] ||
          ![source_attributes[NSFileModificationDate] isEqual:target_attributes[NSFileModificationDate]];
    }

    if (!should_copy) {
      continue;
    }

    NSError *parent_error = nil;
    [file_manager createDirectoryAtPath:target_path.stringByDeletingLastPathComponent
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:&parent_error];
    if (parent_error != nil) {
      if (error_message != nullptr) {
        *error_message = [NSString stringWithFormat:@"Failed to create parent for %@: %@",
                                                    target_path,
                                                    parent_error.localizedDescription];
      }
      return NO;
    }

    NSError *remove_error = nil;
    if ([file_manager fileExistsAtPath:target_path]) {
      [file_manager removeItemAtPath:target_path error:&remove_error];
    }
    if (remove_error != nil) {
      if (error_message != nullptr) {
        *error_message = [NSString stringWithFormat:@"Failed to replace %@: %@",
                                                    target_path,
                                                    remove_error.localizedDescription];
      }
      return NO;
    }

    NSError *copy_error = nil;
    [file_manager copyItemAtPath:source_url.path toPath:target_path error:&copy_error];
    if (copy_error != nil) {
      if (error_message != nullptr) {
        *error_message = [NSString stringWithFormat:@"Failed to copy %@ into %@: %@",
                                                    source_url.path,
                                                    target_path,
                                                    copy_error.localizedDescription];
      }
      return NO;
    }
  }

  return YES;
}

BOOL StripExternalProfileJSONKeys(NSString *path,
                                  NSArray<NSString *> *top_level_keys,
                                  NSString **error_message) {
  if (path.length == 0 || top_level_keys.count == 0) {
    return YES;
  }

  NSFileManager *file_manager = NSFileManager.defaultManager;
  if (![file_manager fileExistsAtPath:path]) {
    return YES;
  }

  NSData *data = [NSData dataWithContentsOfFile:path];
  if (data.length == 0) {
    return YES;
  }

  NSError *json_error = nil;
  id object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&json_error];
  if (![object isKindOfClass:NSMutableDictionary.class]) {
    if (error_message != nullptr) {
      *error_message = [NSString stringWithFormat:@"Failed to parse %@ as a mutable JSON dictionary: %@",
                                                  path,
                                                  json_error.localizedDescription ?: @"invalid JSON"];
    }
    return NO;
  }

  NSMutableDictionary *dictionary = object;
  BOOL changed = NO;
  for (NSString *key in top_level_keys) {
    if (dictionary[key] != nil) {
      [dictionary removeObjectForKey:key];
      changed = YES;
    }
  }

  if (!changed) {
    return YES;
  }

  NSData *serialized =
      [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:&json_error];
  if (serialized.length == 0) {
    if (error_message != nullptr) {
      *error_message = [NSString stringWithFormat:@"Failed to serialize sanitized JSON for %@: %@",
                                                  path,
                                                  json_error.localizedDescription ?: @"serialization failed"];
    }
    return NO;
  }

  NSError *write_error = nil;
  [serialized writeToFile:path options:NSDataWritingAtomic error:&write_error];
  if (write_error != nil) {
    if (error_message != nullptr) {
      *error_message = [NSString stringWithFormat:@"Failed to write sanitized JSON to %@: %@",
                                                  path,
                                                  write_error.localizedDescription];
    }
    return NO;
  }

  return YES;
}

NSMutableDictionary * _Nullable LoadMutableJSONDictionary(NSString *path, NSString **error_message) {
  if (path.length == 0) {
    return nil;
  }

  NSFileManager *file_manager = NSFileManager.defaultManager;
  if (![file_manager fileExistsAtPath:path]) {
    return nil;
  }

  NSData *data = [NSData dataWithContentsOfFile:path];
  if (data.length == 0) {
    return nil;
  }

  NSError *json_error = nil;
  id object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&json_error];
  if (![object isKindOfClass:NSMutableDictionary.class]) {
    if (error_message != nullptr) {
      *error_message = [NSString stringWithFormat:@"Failed to parse %@ as a mutable JSON dictionary: %@",
                                                  path,
                                                  json_error.localizedDescription ?: @"invalid JSON"];
    }
    return nil;
  }

  return object;
}

BOOL WriteMutableJSONDictionary(NSMutableDictionary *dictionary,
                                NSString *path,
                                NSString **error_message) {
  if (dictionary == nil || path.length == 0) {
    return YES;
  }

  NSError *json_error = nil;
  NSData *serialized =
      [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:&json_error];
  if (serialized.length == 0) {
    if (error_message != nullptr) {
      *error_message = [NSString stringWithFormat:@"Failed to serialize sanitized JSON for %@: %@",
                                                  path,
                                                  json_error.localizedDescription ?: @"serialization failed"];
    }
    return NO;
  }

  NSError *write_error = nil;
  [serialized writeToFile:path options:NSDataWritingAtomic error:&write_error];
  if (write_error != nil) {
    if (error_message != nullptr) {
      *error_message = [NSString stringWithFormat:@"Failed to write sanitized JSON to %@: %@",
                                                  path,
                                                  write_error.localizedDescription];
    }
    return NO;
  }

  return YES;
}

BOOL ClearBrowserSigninTokenService(NSString *web_data_path, NSString **error_message) {
  if (![[NSFileManager defaultManager] fileExistsAtPath:web_data_path]) {
    return YES;
  }

  sqlite3 *db = nullptr;
  if (!OpenSQLiteDatabase(web_data_path, &db, error_message)) {
    return NO;
  }

  BOOL ok = SQLiteExec(db, "BEGIN IMMEDIATE TRANSACTION", error_message) &&
            SQLiteExec(db, "DELETE FROM token_service", error_message) &&
            SQLiteExec(db, "COMMIT TRANSACTION", error_message);
  if (!ok) {
    SQLiteExec(db, "ROLLBACK TRANSACTION", nullptr);
  }

  sqlite3_close(db);
  return ok;
}

BOOL RemoveBrowserSigninRuntimeArtifacts(NSString *runtime_profile, NSString **error_message) {
  NSFileManager *file_manager = NSFileManager.defaultManager;
  NSArray<NSString *> *paths_to_remove = @[
    [runtime_profile stringByAppendingPathComponent:@"Accounts"],
    [runtime_profile stringByAppendingPathComponent:@"Account Web Data"],
    [runtime_profile stringByAppendingPathComponent:@"Account Web Data-journal"],
    [runtime_profile stringByAppendingPathComponent:@"Google Profile Picture.png"],
    [runtime_profile stringByAppendingPathComponent:@"Login Data For Account"],
    [runtime_profile stringByAppendingPathComponent:@"Login Data For Account-journal"],
    [runtime_profile stringByAppendingPathComponent:@"Sync Data"],
    [runtime_profile stringByAppendingPathComponent:@"trusted_vault.pb"],
  ];

  for (NSString *path in paths_to_remove) {
    if (path.length == 0 || ![file_manager fileExistsAtPath:path]) {
      continue;
    }

    NSError *remove_error = nil;
    [file_manager removeItemAtPath:path error:&remove_error];
    if (remove_error != nil) {
      if (error_message != nullptr) {
        *error_message = [NSString stringWithFormat:@"Failed to remove browser-signin runtime artifact %@: %@",
                                                    path,
                                                    remove_error.localizedDescription];
      }
      return NO;
    }
  }

  return YES;
}

BOOL SanitizeExternalProfileBrowserSigninState(NSString *runtime_root,
                                               NSString *runtime_profile,
                                               NSString *profile_directory,
                                               NSString **error_message) {
  NSString *preferences_path = [runtime_profile stringByAppendingPathComponent:@"Preferences"];
  NSMutableDictionary *preferences = LoadMutableJSONDictionary(preferences_path, error_message);
  if (preferences != nil) {
    [preferences removeObjectForKey:@"account_info"];
    [preferences removeObjectForKey:@"account_tracker_service_last_update"];
    [preferences removeObjectForKey:@"signin"];

    NSMutableDictionary *google =
        [preferences[@"google"] isKindOfClass:NSMutableDictionary.class] ? preferences[@"google"] : nil;
    NSMutableDictionary *services =
        [google[@"services"] isKindOfClass:NSMutableDictionary.class] ? google[@"services"] : nil;
    [preferences removeObjectForKey:@"gaia_cookie"];
    if (services != nil) {
      [services removeObjectForKey:@"account_id"];
      [services removeObjectForKey:@"last_gaia_id"];
      [services removeObjectForKey:@"last_username"];
      [services removeObjectForKey:@"last_signed_in_username"];
      [services removeObjectForKey:@"signin_scoped_device_id"];
      [services removeObjectForKey:@"syncing_gaia_id_migrated_to_signed_in"];
      [services removeObjectForKey:@"syncing_username_migrated_to_signed_in"];
      [services removeObjectForKey:@"syncing_user_migration_type"];
      [services removeObjectForKey:@"signin"];
      services[@"consented_to_sync"] = @NO;
    }

    if (!WriteMutableJSONDictionary(preferences, preferences_path, error_message)) {
      return NO;
    }
  }

  NSString *local_state_path = [runtime_root stringByAppendingPathComponent:@"Local State"];
  NSMutableDictionary *local_state = LoadMutableJSONDictionary(local_state_path, error_message);
  if (local_state != nil) {
    NSMutableDictionary *profile =
        [local_state[@"profile"] isKindOfClass:NSMutableDictionary.class] ? local_state[@"profile"] : nil;
    NSMutableDictionary *info_cache =
        [profile[@"info_cache"] isKindOfClass:NSMutableDictionary.class] ? profile[@"info_cache"] : nil;
    NSMutableDictionary *entry =
        [info_cache[profile_directory] isKindOfClass:NSMutableDictionary.class] ? info_cache[profile_directory] : nil;
    if (entry != nil) {
      entry[@"gaia_id"] = @"";
      entry[@"gaia_name"] = @"";
      entry[@"gaia_given_name"] = @"";
      entry[@"user_name"] = @"";
      entry[@"is_consented_primary_account"] = @NO;
      [entry removeObjectForKey:@"gaia_picture_file_name"];
      [entry removeObjectForKey:@"last_downloaded_gaia_picture_url_with_size"];
    }

    if (!WriteMutableJSONDictionary(local_state, local_state_path, error_message)) {
      return NO;
    }
  }

  return ClearBrowserSigninTokenService([runtime_profile stringByAppendingPathComponent:@"Web Data"], error_message) &&
         RemoveBrowserSigninRuntimeArtifacts(runtime_profile, error_message);
}

BOOL RemoveExternalProfileRuntimeArtifacts(NSString *runtime_root,
                                           NSString *runtime_profile,
                                           NSString **error_message) {
  NSFileManager *file_manager = NSFileManager.defaultManager;
  NSArray<NSString *> *paths_to_remove = @[
    [runtime_root stringByAppendingPathComponent:@"App Shims"],
  ];

  for (NSString *path in paths_to_remove) {
    if (path.length == 0 || ![file_manager fileExistsAtPath:path]) {
      continue;
    }

    NSError *remove_error = nil;
    [file_manager removeItemAtPath:path error:&remove_error];
    if (remove_error != nil) {
      if (error_message != nullptr) {
        *error_message = [NSString stringWithFormat:@"Failed to remove Chrome-only runtime artifact %@: %@",
                                                    path,
                                                    remove_error.localizedDescription];
      }
      return NO;
    }
  }

  return YES;
}

BOOL PrepareExternalProfileRuntimeState(NSString **error_message) {
  NSString *external_profile = ConfiguredExternalProfilePath();
  if (external_profile.length == 0) {
    return YES;
  }

  NSString *source_root = ExternalProfileSourceUserDataDir(external_profile);
  NSString *profile_directory = external_profile.lastPathComponent;
  NSString *runtime_root = ConfiguredProfileRootPath();
  NSString *runtime_profile = runtime_root.length > 0 ? [runtime_root stringByAppendingPathComponent:profile_directory] : nil;
  if (source_root.length == 0 || runtime_root.length == 0 || runtime_profile.length == 0) {
    if (error_message != nullptr) {
      *error_message = @"GhoDex could not resolve the runtime path for the configured external Chrome profile.";
    }
    return NO;
  }

  NSMutableDictionary *state = ExternalProfileRuntimeState(runtime_root).mutableCopy;
  if (state == nil) {
    state = [NSMutableDictionary dictionary];
  }
  static const NSInteger kExternalProfileSeedVersion = 2;
  static const NSInteger kExternalProfileMigrationVersion = 3;
  NSInteger seed_version = [state[@"seedVersion"] integerValue];
  NSInteger migration_version = [state[@"migrationVersion"] integerValue];
  BOOL runtime_profile_exists = [[NSFileManager defaultManager] fileExistsAtPath:runtime_profile];

  if (seed_version < kExternalProfileSeedVersion || !runtime_profile_exists) {
    if (!CopyChromeUserDataRoot(source_root, runtime_root, profile_directory, YES, error_message)) {
      return NO;
    }
    runtime_profile_exists = [[NSFileManager defaultManager] fileExistsAtPath:runtime_profile];
    if (!runtime_profile_exists) {
      if (error_message != nullptr) {
        *error_message = [NSString stringWithFormat:@"Seeded runtime profile is missing %@ after copy.", runtime_profile];
      }
      return NO;
    }

    if (!RemoveExternalProfileRuntimeArtifacts(runtime_root, runtime_profile, error_message)) {
      return NO;
    }

    state[@"seedVersion"] = @(kExternalProfileSeedVersion);
    state[@"seededAt"] = NSDate.date;
    state[@"sourceProfile"] = external_profile;
    state[@"sourceUserDataDir"] = source_root;
    [state removeObjectForKey:@"migrationVersion"];
    [state removeObjectForKey:@"migrationSummary"];
    migration_version = 0;
  }

  if (migration_version < kExternalProfileMigrationVersion) {
    ExternalProfileCryptoContext crypto_context = LoadExternalProfileCryptoContext();
    ExternalProfileMigrationStats stats;
    if (!RewrapRuntimeProfileData(runtime_profile, crypto_context, &stats, error_message)) {
      return NO;
    }
    if (!SanitizeExternalProfileBrowserSigninState(runtime_root,
                                                   runtime_profile,
                                                   profile_directory,
                                                   error_message)) {
      return NO;
    }

    NSDictionary *summary = @{
      @"cookiesRewrapped" : @(stats.cookiesRewrapped),
      @"tokenServiceRewrapped" : @(stats.tokenServiceRewrapped),
      @"loginPasswordsRewrapped" : @(stats.loginPasswordsRewrapped),
      @"skippedAlreadyChromium" : @(stats.skippedAlreadyChromium),
      @"skippedUnknown" : @(stats.skippedUnknown),
      @"hasChromeKey" : @(crypto_context.chromeKey.length > 0),
      @"hasChromiumKey" : @(crypto_context.chromiumKey.length > 0),
    };
    state[@"migrationVersion"] = @(kExternalProfileMigrationVersion);
    state[@"migrationAt"] = NSDate.date;
    state[@"migrationSummary"] = summary;
    NSLog(@"[CEF] Prepared runtime profile %@ from %@ with os_crypt migration %@",
          runtime_profile,
          external_profile,
          summary);
  }

  if (!WriteExternalProfileRuntimeState(runtime_root, state)) {
    NSLog(@"[CEF] Failed to persist runtime-profile state marker at %@",
          ExternalProfileRuntimeStatePath(runtime_root) ?: @"<none>");
  }

  return YES;
}

pid_t ParsedPIDFromSingletonLockTarget(NSString *target) {
  if (target.length == 0) {
    return 0;
  }

  NSString *lock_name = target.lastPathComponent;
  NSRange separator_range = [lock_name rangeOfString:@"-" options:NSBackwardsSearch];
  if (separator_range.location == NSNotFound ||
      separator_range.location + separator_range.length >= lock_name.length) {
    return 0;
  }

  NSString *pid_string = [lock_name substringFromIndex:separator_range.location + separator_range.length];
  NSInteger pid_value = pid_string.integerValue;
  return pid_value > 0 ? (pid_t)pid_value : 0;
}

BOOL IsProcessAlive(pid_t pid) {
  if (pid <= 0) {
    return NO;
  }

  if (kill(pid, 0) == 0) {
    return YES;
  }

  return errno == EPERM;
}

NSString * _Nullable ProcessPathForPID(pid_t pid) {
  if (pid <= 0) {
    return nil;
  }

  char path_buffer[PROC_PIDPATHINFO_MAXSIZE];
  int length = proc_pidpath(pid, path_buffer, sizeof(path_buffer));
  if (length <= 0) {
    return nil;
  }

  return [NSString stringWithUTF8String:path_buffer];
}

NSString * _Nullable ExternalProfileConflictMessage(void) {
  NSString *external_profile = ConfiguredExternalProfilePath();
  if (external_profile.length == 0) {
    return nil;
  }

  NSString *user_data_dir = external_profile.stringByDeletingLastPathComponent;
  if (user_data_dir.length == 0) {
    return nil;
  }

  NSFileManager *file_manager = NSFileManager.defaultManager;
  NSString *singleton_lock = [user_data_dir stringByAppendingPathComponent:@"SingletonLock"];
  NSString *singleton_cookie = [user_data_dir stringByAppendingPathComponent:@"SingletonCookie"];
  NSString *singleton_socket = [user_data_dir stringByAppendingPathComponent:@"SingletonSocket"];
  auto path_exists_even_if_symlink_is_dangling = ^BOOL(NSString *path) {
    if (path.length == 0) {
      return NO;
    }

    struct stat status = {};
    return lstat(path.fileSystemRepresentation, &status) == 0;
  };

  if (!path_exists_even_if_symlink_is_dangling(singleton_lock)) {
    return nil;
  }

  NSString *lock_target = [file_manager destinationOfSymbolicLinkAtPath:singleton_lock error:nil];
  pid_t lock_pid = ParsedPIDFromSingletonLockTarget(lock_target);
  if (IsProcessAlive(lock_pid)) {
    NSString *process_path = ProcessPathForPID(lock_pid);
    NSString *process_name = process_path.lastPathComponent;
    if (process_name.length == 0) {
      process_name = @"another Chromium process";
    }

    return [NSString
        stringWithFormat:@"The external Chrome profile %@ is already in use by %@ (pid %d). "
                         @"Close Google Chrome and try again.",
                         external_profile,
                         process_name,
                         lock_pid];
  }

  if (path_exists_even_if_symlink_is_dangling(singleton_cookie) &&
      path_exists_even_if_symlink_is_dangling(singleton_socket)) {
    return [NSString stringWithFormat:@"The external Chrome profile %@ appears to still be locked by another "
                                       @"Chrome instance. Close Google Chrome and try again.",
                                       external_profile];
  }

  return nil;
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

BOOL ExternalProfileUsesManagedMirror(NSString *external_profile) {
  return [external_profile containsString:@"/Library/Application Support/GhoDex/CEF/ProfileMirrors/"];
}

NSString * _Nullable ExternalProfileRuntimeRevision(NSString *external_profile) {
  if (external_profile.length == 0) {
    return nil;
  }

  NSFileManager *file_manager = NSFileManager.defaultManager;
  NSString *user_data_dir = ExternalProfileSourceUserDataDir(external_profile);
  NSString *local_state = [user_data_dir stringByAppendingPathComponent:@"Local State"];
  NSDictionary<NSFileAttributeKey, id> *attributes =
      [file_manager attributesOfItemAtPath:local_state error:nil];
  if (attributes.count == 0) {
    attributes = [file_manager attributesOfItemAtPath:user_data_dir error:nil];
  }

  NSDate *modified_at = attributes[NSFileModificationDate];
  NSNumber *file_size = attributes[NSFileSize];
  if (modified_at == nil) {
    return nil;
  }

  return [NSString stringWithFormat:@"%@-%llu-%.6f",
                                    ExternalProfileUsesManagedMirror(external_profile) ? @"mirror" : @"external",
                                    file_size.unsignedLongLongValue,
                                    modified_at.timeIntervalSince1970];
}

NSString * _Nullable CanonicalCEFPath(NSString *path) {
  if (path.length == 0) {
    return nil;
  }

  NSString *standardized = path.stringByStandardizingPath;
  if (standardized.length == 0) {
    return nil;
  }

  char resolved_path[PATH_MAX];
  if (realpath(standardized.fileSystemRepresentation, resolved_path) != nullptr) {
    return [NSString stringWithUTF8String:resolved_path];
  }

  return standardized;
}

NSString *ConfiguredProfileRootPath(void) {
  NSString *external_profile = ConfiguredExternalProfilePath();
  NSString *cef_root = ConfiguredCEFRootPath();
  if (cef_root.length == 0) {
    return nil;
  }

  if (external_profile.length > 0) {
    NSURL *base = [NSURL fileURLWithPath:cef_root isDirectory:YES];
    base = [base URLByAppendingPathComponent:@"Profiles" isDirectory:YES];
    base = [base URLByAppendingPathComponent:@"external" isDirectory:YES];

    NSString *profile_slug = SanitizedPathComponent(external_profile);
    NSString *runtime_revision = ExternalProfileRuntimeRevision(external_profile);
    if (runtime_revision.length > 0) {
      profile_slug = [profile_slug stringByAppendingFormat:@"_%@",
                                                             SanitizedPathComponent(runtime_revision)];
    }
    base = [base URLByAppendingPathComponent:profile_slug isDirectory:YES];

    NSError *error = nil;
    [NSFileManager.defaultManager createDirectoryAtURL:base
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:&error];
    if (error != nil) {
      return nil;
    }

    return CanonicalCEFPath(base.path);
  }

  NSURL *base = [NSURL fileURLWithPath:cef_root isDirectory:YES];
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

  return CanonicalCEFPath(base.path);
}

NSString *ConfiguredProfileCachePath(void) {
  NSString *profile_root = ConfiguredProfileRootPath();
  if (profile_root.length == 0) {
    return nil;
  }

  return [profile_root stringByAppendingPathComponent:@"Cache"];
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
  ApplyRemoteDebuggingCommandLinePolicy(process_type, command_line);

  if (!process_type.empty()) {
    return;
  }

  NSString *external_profile = ConfiguredExternalProfilePath();
  if (external_profile.length == 0) {
    return;
  }

  NSString *user_data_dir = ConfiguredProfileRootPath();
  NSString *profile_directory = external_profile.lastPathComponent;
  if (user_data_dir.length == 0 || profile_directory.length == 0) {
    return;
  }

  command_line->AppendSwitchWithValue("user-data-dir", user_data_dir.UTF8String);
  command_line->AppendSwitchWithValue("profile-directory", profile_directory.UTF8String);
  // Real Chrome profiles carry background services that are useful in Chrome
  // itself but not required for GhoDex's embedded page shell. Disabling the
  // most failure-prone services keeps first-page activation usable. We also
  // force Chromium onto its mock-keychain path because the runtime profile data
  // has already been rewrapped for that derived key during
  // PrepareExternalProfileRuntimeState(); this avoids per-app keychain ACL
  // prompts/failures while preserving copied Chrome auth state inside GhoDex's
  // runtime-owned profile. GhoDex builds do not ship Chrome's OAuth client
  // credentials, so browser-signin services must stay disabled even when the
  // mirrored profile contains Google web cookies and browser-account metadata.
  command_line->AppendSwitch("use-mock-keychain");
  command_line->AppendSwitchWithValue("allow-browser-signin", "false");
  command_line->AppendSwitch("disable-background-networking");
  command_line->AppendSwitch("disable-component-update");
  command_line->AppendSwitch("disable-default-apps");
  command_line->AppendSwitch("disable-extensions");
  command_line->AppendSwitch("disable-sync");
  command_line->AppendSwitchWithValue(
      "disable-features",
      "SegmentationPlatformFeature,OptimizationGuideModelDownloading,MediaRouter");
  NSLog(@"[CEF] Using external Chrome profile %@ (runtime-user-data-dir=%@ profile-directory=%@)",
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
  NSLog(@"[CEF] InitializeGlobal requested initialized=%d initializing=%d external_profile=%@",
        g_cef_initialized.load() ? 1 : 0,
        g_cef_initializing.load() ? 1 : 0,
        ConfiguredExternalProfilePath() ?: @"<none>");
  if (g_cef_initialized.load()) {
    SetLastInitializationError(nil);
    return YES;
  }
  bool expected_initializing = false;
  if (!g_cef_initializing.compare_exchange_strong(expected_initializing, true)) {
    NSLog(@"[CEF] InitializeGlobal skipped because initialization is already in progress.");
    return NO;
  }

  auto clear_initializing = [] {
    g_cef_initializing.store(false);
  };
  SetLastInitializationError(nil);
  if (!EnsureLibraryLoaded()) {
    SetLastInitializationError(@"GhoDex could not load the Chromium Embedded Framework from the configured runtime.");
    clear_initializing();
    return NO;
  }

  NSString *external_profile_conflict = ExternalProfileConflictMessage();
  if (external_profile_conflict.length > 0) {
    NSLog(@"[CEF] Refusing external profile activation: %@", external_profile_conflict);
    SetLastInitializationError(external_profile_conflict);
    clear_initializing();
    return NO;
  }

  NSString *runtime_prepare_error = nil;
  if (!PrepareExternalProfileRuntimeState(&runtime_prepare_error)) {
    NSString *failure =
        runtime_prepare_error ?: @"Chromium could not prepare the configured external Chrome profile for launch.";
    SetLastInitializationError(failure);
    clear_initializing();
    NSLog(@"[CEF] External profile runtime preparation failed: %@", failure);
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

  int remote_debugging_port = ConfiguredRemoteDebuggingPort();
  if (remote_debugging_port > 0) {
    settings.remote_debugging_port = remote_debugging_port;
  }

  NSString *profile_root = ConfiguredProfileRootPath();
  if (profile_root.length > 0) {
    NSString *cache_path = [profile_root stringByAppendingPathComponent:@"Cache"];
    CefString(&settings.root_cache_path) = profile_root.UTF8String;
    CefString(&settings.cache_path) = cache_path.UTF8String;
    settings.persist_session_cookies = true;
  }

  NSLog(@"[CEF] Initializing framework=%@ profile=%@ cache=%@ external_profile=%@ bundle=%@ remote_debug_port=%d",
        framework_path ?: @"<none>",
        profile_root ?: @"<none>",
        (profile_root.length > 0 ? [profile_root stringByAppendingPathComponent:@"Cache"] : nil) ?: @"<none>",
        ConfiguredExternalProfilePath() ?: @"<none>",
        bundle_path ?: @"<none>",
        remote_debugging_port);

  BOOL initialized = CefInitialize(args.mainArgs(), settings, g_cef_app.get(), nullptr) ? YES : NO;
  g_cef_initialized.store(initialized == YES);
  clear_initializing();
  if (!initialized) {
    NSString *failure =
        ExternalProfileConflictMessage() ?: (ConfiguredExternalProfilePath().length > 0
                                                 ? @"Chromium could not activate with the configured external Chrome profile."
                                                 : @"Chromium could not be activated in this app session.");
    SetLastInitializationError(failure);
    NSLog(@"[CEF] CefInitialize returned NO: %@", failure);
  } else {
    SetLastInitializationError(nil);
    NSLog(@"[CEF] CefInitialize returned YES.");
  }
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

BOOL GhoDexCEFIsInitializing(void) {
  return g_cef_initializing.load() ? YES : NO;
}

NSString * _Nullable GhoDexCEFLastInitializationError(void) {
  return CopyLastInitializationError();
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

BOOL GhoDexCEFIsInitializing(void) {
  return NO;
}

NSString * _Nullable GhoDexCEFLastInitializationError(void) {
  return nil;
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

- (void)executeJavaScript:(NSString *)javaScript frameName:(NSString *)frameName {
}

- (void)evaluateJavaScript:(NSString *)javaScript completion:(GhoDexCEFJavaScriptEvaluationCompletion)completion {
  [self evaluateJavaScript:javaScript frameName:nil completion:completion];
}

- (void)evaluateJavaScript:(NSString *)javaScript
                 frameName:(NSString *)frameName
                completion:(GhoDexCEFJavaScriptEvaluationCompletion)completion {
  if (completion != nil) {
    NSError *error = [NSError errorWithDomain:GhoDexCEFControlErrorDomain
                                         code:GhoDexCEFControlErrorCodeBridgeUnavailable
                                     userInfo:@{
                                       NSLocalizedDescriptionKey : @"CEF support is disabled in this build."
                                     }];
    completion(nil, error);
  }
}

- (void)listFramesWithCompletion:(GhoDexCEFJavaScriptEvaluationCompletion)completion {
  if (completion != nil) {
    NSError *error = [NSError errorWithDomain:GhoDexCEFControlErrorDomain
                                         code:GhoDexCEFControlErrorCodeBridgeUnavailable
                                     userInfo:@{
                                       NSLocalizedDescriptionKey : @"CEF support is disabled in this build."
                                     }];
    completion(nil, error);
  }
}

- (BOOL)performTrustedClickAtX:(double)x
                             y:(double)y
                          error:(NSError * _Nullable * _Nullable)error {
  (void)x;
  (void)y;
  if (error != nil) {
    *error = [NSError errorWithDomain:GhoDexCEFControlErrorDomain
                                 code:GhoDexCEFControlErrorCodeBridgeUnavailable
                             userInfo:@{
                               NSLocalizedDescriptionKey : @"CEF support is disabled in this build."
                             }];
  }
  return NO;
}

- (BOOL)resolveDialogRequestID:(NSString *)requestID
                      accepted:(BOOL)accepted
                     userInput:(NSString *)userInput
                         error:(NSError * _Nullable * _Nullable)error {
  (void)requestID;
  (void)accepted;
  (void)userInput;
  if (error != nil) {
    *error = [NSError errorWithDomain:GhoDexCEFControlErrorDomain
                                 code:GhoDexCEFControlErrorCodeBridgeUnavailable
                             userInfo:@{
                               NSLocalizedDescriptionKey : @"CEF support is disabled in this build."
                             }];
  }
  return NO;
}

- (BOOL)resolvePermissionRequestID:(NSString *)requestID
                            result:(NSString *)result
                             error:(NSError * _Nullable * _Nullable)error {
  (void)requestID;
  (void)result;
  if (error != nil) {
    *error = [NSError errorWithDomain:GhoDexCEFControlErrorDomain
                                 code:GhoDexCEFControlErrorCodeBridgeUnavailable
                             userInfo:@{
                               NSLocalizedDescriptionKey : @"CEF support is disabled in this build."
                             }];
  }
  return NO;
}

- (BOOL)resolveAuthRequestID:(NSString *)requestID
                    accepted:(BOOL)accepted
                    username:(NSString *)username
                    password:(NSString *)password
                       error:(NSError * _Nullable * _Nullable)error {
  (void)requestID;
  (void)accepted;
  (void)username;
  (void)password;
  if (error != nil) {
    *error = [NSError errorWithDomain:GhoDexCEFControlErrorDomain
                                 code:GhoDexCEFControlErrorCodeBridgeUnavailable
                             userInfo:@{
                               NSLocalizedDescriptionKey : @"CEF support is disabled in this build."
                             }];
  }
  return NO;
}

- (BOOL)resolveCertificateRequestID:(NSString *)requestID
                           accepted:(BOOL)accepted
                              error:(NSError * _Nullable * _Nullable)error {
  (void)requestID;
  (void)accepted;
  if (error != nil) {
    *error = [NSError errorWithDomain:GhoDexCEFControlErrorDomain
                                 code:GhoDexCEFControlErrorCodeBridgeUnavailable
                             userInfo:@{
                               NSLocalizedDescriptionKey : @"CEF support is disabled in this build."
                             }];
  }
  return NO;
}

- (BOOL)cancelDownloadID:(NSString *)downloadID
                   error:(NSError * _Nullable * _Nullable)error {
  (void)downloadID;
  if (error != nil) {
    *error = [NSError errorWithDomain:GhoDexCEFControlErrorDomain
                                 code:GhoDexCEFControlErrorCodeBridgeUnavailable
                             userInfo:@{
                               NSLocalizedDescriptionKey : @"CEF support is disabled in this build."
                             }];
  }
  return NO;
}

@end

#endif
