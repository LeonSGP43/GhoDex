import Foundation

enum BrowserControlScriptBuilder {
    static func script(for request: BrowserControlRequest) throws -> String {
        switch request.command {
        case .query:
            return try queryScript(selector: requiredValue("selector", from: request))
        case .click:
            return try clickScript(selector: requiredValue("selector", from: request))
        case .typeText:
            return try typeTextScript(
                selector: requiredValue("selector", from: request),
                text: requiredValue("text", from: request)
            )
        case .waitForSelector:
            return try waitForSelectorScript(
                selector: requiredValue("selector", from: request),
                state: waitState(from: request),
                timeoutMS: max(0, request.timeoutMS ?? 5000)
            )
        default:
            throw BrowserControlScriptBuilderError.unsupportedCommand(request.command)
        }
    }

    private static func queryScript(selector: String) throws -> String {
        let selectorLiteral = try javaScriptStringLiteral(selector)
        return """
        (() => {
          const selector = \(selectorLiteral);
          const element = document.querySelector(selector);
          if (!element) {
            return { found: false, selector };
          }

          return {
            found: true,
            selector,
            tagName: element.tagName ?? null,
            text: element.innerText ?? element.textContent ?? "",
            value: ("value" in element) ? element.value : null,
            html: element.outerHTML ?? null
          };
        })()
        """
    }

    private static func clickScript(selector: String) throws -> String {
        let selectorLiteral = try javaScriptStringLiteral(selector)
        return """
        (() => {
          const selector = \(selectorLiteral);
          const element = document.querySelector(selector);
          if (!element) {
            throw new Error(`No element matched selector: ${selector}`);
          }

          if (typeof element.scrollIntoView === "function") {
            element.scrollIntoView({ block: "center", inline: "center" });
          }

          element.click();
          return { clicked: true, selector };
        })()
        """
    }

    private static func typeTextScript(selector: String, text: String) throws -> String {
        let selectorLiteral = try javaScriptStringLiteral(selector)
        let textLiteral = try javaScriptStringLiteral(text)
        return """
        (() => {
          const selector = \(selectorLiteral);
          const nextValue = \(textLiteral);
          const element = document.querySelector(selector);
          if (!element) {
            throw new Error(`No element matched selector: ${selector}`);
          }

          if (!("value" in element)) {
            throw new Error(`Element does not support value assignment: ${selector}`);
          }

          if (typeof element.focus === "function") {
            element.focus();
          }

          element.value = nextValue;
          element.dispatchEvent(new Event("input", { bubbles: true }));
          element.dispatchEvent(new Event("change", { bubbles: true }));
          return { typed: true, selector, value: element.value };
        })()
        """
    }

    private static func waitForSelectorScript(
        selector: String,
        state: String,
        timeoutMS: Int
    ) throws -> String {
        let selectorLiteral = try javaScriptStringLiteral(selector)
        let stateLiteral = try javaScriptStringLiteral(state)
        return """
        (() => {
          const selector = \(selectorLiteral);
          const state = \(stateLiteral);
          const timeoutMS = \(timeoutMS);
          const startedAt = Date.now();

          const snapshot = (element) => ({
            found: true,
            timedOut: false,
            selector,
            state,
            elapsedMS: Date.now() - startedAt,
            tagName: element?.tagName ?? null,
            text: element?.innerText ?? element?.textContent ?? ""
          });

          const locateElement = () => {
            const element = document.querySelector(selector);
            if (!element) {
              return null;
            }

            if (state !== "present") {
              throw new Error(`Unsupported waitForSelector state: ${state}`);
            }

            return element;
          };

          return new Promise((resolve) => {
            try {
              const initialMatch = locateElement();
              if (initialMatch) {
                resolve(snapshot(initialMatch));
                return;
              }
            } catch (error) {
              throw error;
            }

            const rootNode = document.documentElement ?? document.body ?? document;
            let settled = false;
            let timeoutID = 0;

            const finish = (payload) => {
              if (settled) {
                return;
              }

              settled = true;
              observer.disconnect();
              clearTimeout(timeoutID);
              resolve(payload);
            };

            const observer = new MutationObserver(() => {
              try {
                const match = locateElement();
                if (match) {
                  finish(snapshot(match));
                }
              } catch (error) {
                finish({
                  found: false,
                  timedOut: false,
                  selector,
                  state,
                  elapsedMS: Date.now() - startedAt,
                  error: error instanceof Error ? error.message : String(error)
                });
              }
            });

            observer.observe(rootNode, {
              subtree: true,
              childList: true,
              attributes: true,
            });

            timeoutID = window.setTimeout(() => {
              finish({
                found: false,
                timedOut: true,
                selector,
                state,
                elapsedMS: Date.now() - startedAt
              });
            }, timeoutMS);
          });
        })()
        """
    }

    private static func requiredValue(_ key: String, from request: BrowserControlRequest) throws -> String {
        guard let value = request.payload[key], !value.isEmpty else {
            throw BrowserControlScriptBuilderError.missingPayload(key)
        }
        return value
    }

    private static func waitState(from request: BrowserControlRequest) throws -> String {
        guard let state = request.payload["state"], !state.isEmpty else {
            return "present"
        }

        if state == "present" {
            return state
        }

        throw BrowserControlScriptBuilderError.unsupportedWaitState(state)
    }

    private static func javaScriptStringLiteral(_ value: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [value], options: [])
        guard let encoded = String(bytes: data, encoding: .utf8) else {
            throw BrowserControlScriptBuilderError.stringEncodingFailed
        }
        return String(encoded.dropFirst().dropLast())
    }
}

enum BrowserControlScriptBuilderError: LocalizedError {
    case missingPayload(String)
    case unsupportedCommand(BrowserControlCommandKind)
    case unsupportedWaitState(String)
    case stringEncodingFailed

    var errorDescription: String? {
        switch self {
        case let .missingPayload(key):
            return "The browser control command requires a non-empty \(key) payload."
        case let .unsupportedCommand(command):
            return "No DOM control script builder exists for the \(command.rawValue) command."
        case let .unsupportedWaitState(state):
            return "The waitForSelector command does not support the \(state) state yet."
        case .stringEncodingFailed:
            return "The browser control script could not be encoded as UTF-8 JavaScript."
        }
    }
}
