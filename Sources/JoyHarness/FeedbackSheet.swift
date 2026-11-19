import AppKit
import CoreBluetooth
import Darwin
import SwiftUI

@MainActor
struct FeedbackSheet: View {
    let model: DashboardModel
    var endpoint = IssueFeedback.endpoint

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @FocusState private var titleFocused: Bool
    @State private var title = ""
    @State private var description = ""
    @State private var includesDiagnostics = false
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var browserStatus: String?
    @State private var issue: IssueFeedback.CreatedIssue?

    init(model: DashboardModel, endpoint: URL? = IssueFeedback.endpoint, showsDiagnosticsInitially: Bool = false) {
        self.model = model
        self.endpoint = endpoint
        _includesDiagnostics = State(initialValue: showsDiagnosticsInitially)
    }

    private var environmentSummary: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "JoyHarness \(AppInfo.version) (\(AppInfo.build)) · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · CPU \(Self.cpuArchitecture) · \(model.controllerProfile.name)"
    }

    private static let cpuArchitecture: String = {
        #if arch(arm64)
        return "arm64"
        #else
        var translated: Int32 = 0
        var size = MemoryLayout.size(ofValue: translated)
        let result = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0)
        return result == 0 && translated == 1 ? "arm64" : "x86_64"
        #endif
    }()

    private var diagnostics: String {
        let devices = model.devices.map { "\($0.profile.name): \($0.status)" }.joined(separator: "\n")
        return [
            "选中手柄：\(model.controllerTitle)",
            "映射：\(model.enabled ? "启用" : "暂停")",
            "辅助功能：\(model.accessibility ? "已授权" : "未授权")",
            "输入监控：\(model.inputMonitoring ? "已授权" : "未授权")",
            "蓝牙：\(CBManager.authorization == .allowedAlways ? "已授权" : "未授权")",
            "一代 HID：\(model.hidStatus)",
            "二代 BLE：\(model.bleStatus)",
            devices.isEmpty ? "发现的手柄：无" : "发现的手柄：\n\(devices)"
        ].joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsStyle.Spacing.groups) {
            Text("提交反馈").font(SettingsStyle.Typography.dialogTitle)
            if let issue {
                Text("已创建 Issue #\(issue.number)")
                HStack {
                    Link("查看 GitHub Issue", destination: issue.url)
                    Spacer()
                    Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            } else {
                form
            }
        }
        .padding(SettingsStyle.pagePadding)
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        .interactiveDismissDisabled(isSubmitting)
        .onAppear { titleFocused = true }
    }

    private var form: some View {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = includesDiagnostics ? "\n\n### 诊断信息\n\n```text\n\(diagnostics)\n```" : ""
        let feedback = IssueFeedback(title: trimmedTitle, body: "\(trimmedDescription)\n\n### 运行环境\n\n\(environmentSummary)\(details)")
        let draft = endpoint == nil ? feedback.githubDraft : nil

        return VStack(alignment: .leading, spacing: SettingsStyle.Spacing.groups) {
            VStack(alignment: .leading, spacing: SettingsStyle.Spacing.controls) {
                VStack(alignment: .leading, spacing: SettingsStyle.Spacing.inline) {
                    Text("标题").font(.callout.weight(.medium))
                    TextField("简要概括问题或建议", text: $title)
                        .accessibilityLabel("标题")
                        .focused($titleFocused)
                }
                VStack(alignment: .leading, spacing: SettingsStyle.Spacing.inline) {
                    Text("描述").font(.callout.weight(.medium))
                    TextEditor(text: $description)
                        .font(.body)
                        .frame(height: 110)
                        .border(Color.secondary.opacity(0.25))
                        .accessibilityLabel("描述")
                    Text("报告问题时，请尽量附上复现步骤。").foregroundStyle(.secondary)
                }
                Text(environmentSummary).foregroundStyle(.secondary).textSelection(.enabled)
                Toggle("附上诊断信息", isOn: $includesDiagnostics)
                    .toggleStyle(.checkbox)
                if includesDiagnostics {
                    Text(diagnostics)
                        .font(.system(.callout, design: .monospaced))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SettingsStyle.controlPadding)
                        .background(SettingsStyle.subtle, in: RoundedRectangle(cornerRadius: SettingsStyle.controlRadius))
                }
            }
            .disabled(isSubmitting)

            Text(draft == nil ? "提交内容会公开显示在 GitHub Issues。" : "内容会在你到 GitHub 确认发布后公开。")
                .foregroundStyle(.secondary)

            if let message = feedback.validationMessage ?? error {
                Text(message).foregroundStyle(.red)
            } else if let browserStatus {
                Text(browserStatus).foregroundStyle(.secondary)
            }
            HStack {
                if isSubmitting {
                    ProgressView().controlSize(.small)
                    Text("正在提交…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction).disabled(isSubmitting)
                Button(actionTitle(needsBodyPaste: draft?.needsBodyPaste == true)) {
                    if let endpoint {
                        submit(feedback, to: endpoint)
                    } else if let draft {
                        openDraft(draft, feedback: feedback)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting || trimmedTitle.isEmpty || trimmedDescription.isEmpty || feedback.validationMessage != nil)
            }
        }
        .font(.callout)
    }

    private func actionTitle(needsBodyPaste: Bool) -> String {
        if endpoint != nil { return "提交到 GitHub" }
        return needsBodyPaste ? "复制正文并前往 GitHub" : "前往 GitHub…"
    }

    private func openDraft(_ draft: (url: URL, needsBodyPaste: Bool), feedback: IssueFeedback) {
        error = nil
        browserStatus = nil
        if draft.needsBodyPaste {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(feedback.body, forType: .string)
        }
        openURL(draft.url) { accepted in
            if accepted {
                browserStatus = draft.needsBodyPaste ? "正文已复制，请粘贴到 GitHub 的描述栏后发布。" : "已打开 GitHub，请在浏览器中确认发布。"
            } else {
                error = "无法打开 GitHub，请检查默认浏览器后重试。"
            }
        }
    }

    private func submit(_ feedback: IssueFeedback, to endpoint: URL) {
        isSubmitting = true
        error = nil
        Task {
            defer { isSubmitting = false }
            do {
                issue = try await feedback.submit(to: endpoint)
            } catch IssueFeedback.SubmissionError.rateLimited {
                self.error = "提交过于频繁，请稍后重试。"
            } catch {
                self.error = "未能确认提交结果。请先查看 GitHub Issues，再决定是否重试。"
            }
        }
    }
}
