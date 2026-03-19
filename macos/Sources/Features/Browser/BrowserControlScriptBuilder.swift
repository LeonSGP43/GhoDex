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
        case .getDOMSnapshot:
            return try domSnapshotScript(
                selector: optionalValue("selector", from: request),
                maxDepth: max(0, intValue("maxDepth", from: request) ?? 2),
                includeText: boolValue("includeText", from: request) ?? true
            )
        case .getText:
            return try textScript(selector: requiredValue("selector", from: request))
        case .getAttributes:
            return try attributesScript(selector: requiredValue("selector", from: request))
        case .getBoundingBox:
            return try boundingBoxScript(selector: requiredValue("selector", from: request))
        case .batchDOMCommands:
            return try batchDOMCommandsScript(commandsJSON: requiredValue("commandsJSON", from: request))
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

    private static func domSnapshotScript(
        selector: String?,
        maxDepth: Int,
        includeText: Bool
    ) throws -> String {
        let selectorLiteral = try nullableJavaScriptStringLiteral(selector)
        return """
        (() => {
          const selector = \(selectorLiteral);
          const maxDepth = \(maxDepth);
          const includeText = \(includeText ? "true" : "false");
          const root = selector ? document.querySelector(selector) : document.documentElement;
          if (!root) {
            return { found: false, selector, maxDepth };
          }

          const snapshotNode = (node, depth) => {
            if (depth > maxDepth) {
              return null;
            }

            const children = [];
            for (const child of Array.from(node.children ?? [])) {
              const childSnapshot = snapshotNode(child, depth + 1);
              if (childSnapshot) {
                children.push(childSnapshot);
              }
            }

            return {
              tagName: node.tagName ?? null,
              id: node.id || null,
              className: node.className || null,
              text: includeText ? (node.innerText ?? node.textContent ?? "") : null,
              attributes: Object.fromEntries(Array.from(node.attributes ?? []).map((attribute) => [attribute.name, attribute.value])),
              childCount: node.children?.length ?? 0,
              children,
            };
          };

          return {
            found: true,
            selector,
            maxDepth,
            includeText,
            snapshot: snapshotNode(root, 0)
          };
        })()
        """
    }

    private static func textScript(selector: String) throws -> String {
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
            text: element.innerText ?? element.textContent ?? ""
          };
        })()
        """
    }

    private static func attributesScript(selector: String) throws -> String {
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
            attributes: Object.fromEntries(Array.from(element.attributes ?? []).map((attribute) => [attribute.name, attribute.value]))
          };
        })()
        """
    }

    private static func boundingBoxScript(selector: String) throws -> String {
        let selectorLiteral = try javaScriptStringLiteral(selector)
        return """
        (() => {
          const selector = \(selectorLiteral);
          const element = document.querySelector(selector);
          if (!element) {
            return { found: false, selector };
          }

          const rect = element.getBoundingClientRect();
          return {
            found: true,
            selector,
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height,
            top: rect.top,
            right: rect.right,
            bottom: rect.bottom,
            left: rect.left,
            scrollX: window.scrollX,
            scrollY: window.scrollY,
            viewportWidth: window.innerWidth,
            viewportHeight: window.innerHeight
          };
        })()
        """
    }

    private static func batchDOMCommandsScript(commandsJSON: String) throws -> String {
        let commands = try decodeBatchCommands(from: commandsJSON)
        let data = try JSONEncoder().encode(commands)
        guard let normalizedCommandsJSON = String(data: data, encoding: .utf8) else {
            throw BrowserControlScriptBuilderError.stringEncodingFailed
        }

        let commandsJSONLiteral = try javaScriptStringLiteral(normalizedCommandsJSON)
        return """
        (() => {
          const commands = JSON.parse(\(commandsJSONLiteral));
          const snapshotNode = (node, depth, maxDepth, includeText) => {
            if (!node || depth > maxDepth) {
              return null;
            }

            const children = [];
            for (const child of Array.from(node.children ?? [])) {
              const childSnapshot = snapshotNode(child, depth + 1, maxDepth, includeText);
              if (childSnapshot) {
                children.push(childSnapshot);
              }
            }

            return {
              tagName: node.tagName ?? null,
              id: node.id || null,
              className: node.className || null,
              text: includeText ? (node.innerText ?? node.textContent ?? "") : null,
              attributes: Object.fromEntries(Array.from(node.attributes ?? []).map((attribute) => [attribute.name, attribute.value])),
              childCount: node.children?.length ?? 0,
              children,
            };
          };

          const findElement = (selector) => {
            if (typeof selector !== "string" || selector.length === 0) {
              throw new Error("Each DOM batch command requires a non-empty selector.");
            }
            return document.querySelector(selector);
          };

          const execute = (command) => {
            const id = command.id;
            const kind = command.command;

            try {
              let value;
              switch (kind) {
              case "query": {
                const selector = command.selector;
                const element = findElement(selector);
                value = element ? {
                  found: true,
                  selector,
                  tagName: element.tagName ?? null,
                  text: element.innerText ?? element.textContent ?? "",
                  value: ("value" in element) ? element.value : null,
                  html: element.outerHTML ?? null
                } : {
                  found: false,
                  selector
                };
                break;
              }
              case "click": {
                const selector = command.selector;
                const element = findElement(selector);
                if (!element) {
                  throw new Error(`No element matched selector: ${selector}`);
                }

                if (typeof element.scrollIntoView === "function") {
                  element.scrollIntoView({ block: "center", inline: "center" });
                }

                element.click();
                value = { clicked: true, selector };
                break;
              }
              case "typeText": {
                const selector = command.selector;
                const element = findElement(selector);
                if (!element) {
                  throw new Error(`No element matched selector: ${selector}`);
                }

                if (!("value" in element)) {
                  throw new Error(`Element does not support value assignment: ${selector}`);
                }

                if (typeof element.focus === "function") {
                  element.focus();
                }

                const nextValue = typeof command.text === "string" ? command.text : "";
                element.value = nextValue;
                element.dispatchEvent(new Event("input", { bubbles: true }));
                element.dispatchEvent(new Event("change", { bubbles: true }));
                value = { typed: true, selector, value: element.value };
                break;
              }
              case "getText": {
                const selector = command.selector;
                const element = findElement(selector);
                value = element ? {
                  found: true,
                  selector,
                  text: element.innerText ?? element.textContent ?? ""
                } : {
                  found: false,
                  selector
                };
                break;
              }
              case "getAttributes": {
                const selector = command.selector;
                const element = findElement(selector);
                value = element ? {
                  found: true,
                  selector,
                  attributes: Object.fromEntries(Array.from(element.attributes ?? []).map((attribute) => [attribute.name, attribute.value]))
                } : {
                  found: false,
                  selector
                };
                break;
              }
              case "getBoundingBox": {
                const selector = command.selector;
                const element = findElement(selector);
                if (!element) {
                  value = { found: false, selector };
                  break;
                }

                const rect = element.getBoundingClientRect();
                value = {
                  found: true,
                  selector,
                  x: rect.x,
                  y: rect.y,
                  width: rect.width,
                  height: rect.height,
                  top: rect.top,
                  right: rect.right,
                  bottom: rect.bottom,
                  left: rect.left,
                  scrollX: window.scrollX,
                  scrollY: window.scrollY,
                  viewportWidth: window.innerWidth,
                  viewportHeight: window.innerHeight
                };
                break;
              }
              case "getDOMSnapshot": {
                const selector = typeof command.selector === "string" && command.selector.length > 0 ? command.selector : null;
                const maxDepth = Number.isInteger(command.maxDepth) ? Math.max(0, command.maxDepth) : 2;
                const includeText = typeof command.includeText === "boolean" ? command.includeText : true;
                const root = selector ? document.querySelector(selector) : document.documentElement;
                value = root ? {
                  found: true,
                  selector,
                  maxDepth,
                  includeText,
                  snapshot: snapshotNode(root, 0, maxDepth, includeText)
                } : {
                  found: false,
                  selector,
                  maxDepth
                };
                break;
              }
              default:
                throw new Error(`Unsupported DOM batch command: ${kind}`);
              }

              return {
                id,
                command: kind,
                ok: true,
                valueJSON: JSON.stringify(value),
                errorMessage: null
              };
            } catch (error) {
              return {
                id,
                command: kind,
                ok: false,
                valueJSON: null,
                errorMessage: error instanceof Error ? error.message : String(error)
              };
            }
          };

          return {
            results: commands.map(execute)
          };
        })()
        """
    }

    private static func requiredValue(_ key: String, from request: BrowserControlRequest) throws -> String {
        guard let value = request.payload[key], !value.isEmpty else {
            throw BrowserControlScriptBuilderError.missingPayload(key)
        }
        return value
    }

    private static func optionalValue(_ key: String, from request: BrowserControlRequest) -> String? {
        guard let value = request.payload[key], !value.isEmpty else {
            return nil
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

    private static func intValue(_ key: String, from request: BrowserControlRequest) throws -> Int? {
        guard let rawValue = optionalValue(key, from: request) else {
            return nil
        }
        guard let value = Int(rawValue) else {
            throw BrowserControlScriptBuilderError.invalidNumericPayload(key)
        }
        return value
    }

    private static func boolValue(_ key: String, from request: BrowserControlRequest) throws -> Bool? {
        guard let rawValue = optionalValue(key, from: request) else {
            return nil
        }

        switch rawValue.lowercased() {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            throw BrowserControlScriptBuilderError.invalidBooleanPayload(key)
        }
    }

    private static func javaScriptStringLiteral(_ value: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [value], options: [])
        guard let encoded = String(bytes: data, encoding: .utf8) else {
            throw BrowserControlScriptBuilderError.stringEncodingFailed
        }
        return String(encoded.dropFirst().dropLast())
    }

    private static func nullableJavaScriptStringLiteral(_ value: String?) throws -> String {
        guard let value else {
            return "null"
        }
        return try javaScriptStringLiteral(value)
    }

    private static func decodeBatchCommands(from commandsJSON: String) throws -> [BrowserDOMBatchCommand] {
        guard let data = commandsJSON.data(using: .utf8) else {
            throw BrowserControlScriptBuilderError.invalidBatchCommandsPayload
        }

        let commands: [BrowserDOMBatchCommand]
        do {
            commands = try JSONDecoder().decode([BrowserDOMBatchCommand].self, from: data)
        } catch {
            throw BrowserControlScriptBuilderError.invalidBatchCommandsPayload
        }

        guard !commands.isEmpty else {
            throw BrowserControlScriptBuilderError.emptyBatchCommandList
        }

        try commands.forEach(validateBatchCommand(_:))
        return commands
    }

    private static func validateBatchCommand(_ command: BrowserDOMBatchCommand) throws {
        switch command.command {
        case .query, .click, .getText, .getAttributes, .getBoundingBox:
            guard let selector = command.selector, !selector.isEmpty else {
                throw BrowserControlScriptBuilderError.invalidBatchCommand(command.command, key: "selector")
            }
        case .typeText:
            guard let selector = command.selector, !selector.isEmpty else {
                throw BrowserControlScriptBuilderError.invalidBatchCommand(command.command, key: "selector")
            }
            guard command.text != nil else {
                throw BrowserControlScriptBuilderError.invalidBatchCommand(command.command, key: "text")
            }
        case .getDOMSnapshot:
            break
        }
    }
}

enum BrowserControlScriptBuilderError: LocalizedError {
    case missingPayload(String)
    case unsupportedCommand(BrowserControlCommandKind)
    case unsupportedWaitState(String)
    case invalidNumericPayload(String)
    case invalidBooleanPayload(String)
    case invalidBatchCommandsPayload
    case emptyBatchCommandList
    case invalidBatchCommand(BrowserDOMBatchCommandKind, key: String)
    case stringEncodingFailed

    var errorDescription: String? {
        switch self {
        case let .missingPayload(key):
            return "The browser control command requires a non-empty \(key) payload."
        case let .unsupportedCommand(command):
            return "No DOM control script builder exists for the \(command.rawValue) command."
        case let .unsupportedWaitState(state):
            return "The waitForSelector command does not support the \(state) state yet."
        case let .invalidNumericPayload(key):
            return "The \(key) payload must be a valid integer."
        case let .invalidBooleanPayload(key):
            return "The \(key) payload must be a valid boolean."
        case .invalidBatchCommandsPayload:
            return "The commandsJSON payload must be a valid JSON array of DOM batch commands."
        case .emptyBatchCommandList:
            return "The browser DOM batch requires at least one command."
        case let .invalidBatchCommand(command, key):
            return "The \(command.rawValue) batch command requires a non-empty \(key) payload."
        case .stringEncodingFailed:
            return "The browser control script could not be encoded as UTF-8 JavaScript."
        }
    }
}
