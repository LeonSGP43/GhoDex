#import "GhoDexCEFBridge.h"

#if GHODEX_CEF_ENABLED

#include <algorithm>
#include <atomic>
#include <string>
#include <vector>

#include <dispatch/dispatch.h>

#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/wrapper/cef_library_loader.h"
#include "include/wrapper/cef_helpers.h"

namespace {
std::atomic<int64_t> g_message_pump_generation{0};
std::atomic<bool> g_cef_initialized{false};
std::atomic<bool> g_cef_initializing{false};
std::atomic<bool> g_cef_library_loaded{false};
dispatch_source_t g_message_pump_timer = nullptr;

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

class GhoDexCEFApp final : public CefApp, public CefBrowserProcessHandler {
public:
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
    return this;
  }

  void OnBeforeCommandLineProcessing(
      const CefString &process_type,
      CefRefPtr<CefCommandLine> command_line) override;

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

  void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &title) override;

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    browser_ = browser;
    NSLog(@"[CEF] Browser created for %@", owner_);
    EmitState(browser->IsLoading(), browser->CanGoBack(), browser->CanGoForward());
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    if (browser_ && browser_->GetIdentifier() == browser->GetIdentifier()) {
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
}
@end

@implementation GhoDexCEFView

- (instancetype)initWithInitialURLString:(NSString *)initialURLString {
  self = [super initWithFrame:NSZeroRect];
  if (self) {
    _initialURLString = [initialURLString copy];
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

- (void)notifyTitle:(NSString *)title {
  [self.delegate cefView:self didUpdateTitle:title];
}

- (void)notifyURL:(NSString *)url canGoBack:(BOOL)canGoBack canGoForward:(BOOL)canGoForward isLoading:(BOOL)isLoading {
  [self.delegate cefView:self didUpdateURL:url canGoBack:canGoBack canGoForward:canGoForward isLoading:isLoading];
}

- (void)notifyOpenURLInNewTab:(NSString *)urlString {
  [self.delegate cefView:self requestOpenURLInNewTab:urlString];
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

void GhoDexCEFClient::OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool isLoading, bool canGoBack, bool canGoForward) {
  NSLog(@"[CEF] Loading state changed: loading=%d back=%d forward=%d url=%s",
        isLoading,
        canGoBack,
        canGoForward,
        browser ? browser->GetMainFrame()->GetURL().ToString().c_str() : "");
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

@end

#endif
