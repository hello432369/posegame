import SwiftUI

struct ContentView: View {
    @EnvironmentObject var mgr: KeyBridgeManager

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                column("身体", systemImage: "figure.stand", color: .green,
                        active: mgr.bodyActions, category: "body")
                Divider()
                column("手势", systemImage: "hand.raised", color: .cyan,
                        active: mgr.handActions, category: "hand")
                Divider()
                column("脸部", systemImage: "face.smiling", color: .pink,
                        active: mgr.faceActions, category: "face")
            }
            Divider()
            if !mgr.log.isEmpty {
                logPanel
                Divider()
            }
            bottomBar
        }
    }

    func column(_ title: String, systemImage: String, color: Color,
                active: [String], category: String) -> some View {
        let activeSet = Set(active)
        // 以配置包分类为准（不动），不管有没有按键映射
        let items: [String]
        if category == "body" { items = mgr.configBody }
        else if category == "hand" { items = mgr.configHand }
        else { items = mgr.configFace }

        return VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline).foregroundColor(color)
                .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if items.isEmpty {
                        Text("暂无绑定").font(.caption).foregroundColor(.secondary)
                    }
                    ForEach(items, id: \.self) { action in
                        HStack {
                            Text(action)
                                .font(.subheadline)
                                .foregroundColor(activeSet.contains(action) ? color : .primary)
                                .fontWeight(activeSet.contains(action) ? .bold : .regular)
                            Spacer()
                            if let m = mgr.config.mappings[action] {
                                Text("[\(m.key)]")
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                            } else {
                                Text("未绑定")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.horizontal, 4)
                        .background(activeSet.contains(action) ? color.opacity(0.15) : Color.clear)
                        .cornerRadius(4)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var toolbar: some View {
        HStack {
            Circle().fill(mgr.running ? Color.green : Color.red).frame(width: 10, height: 10)
            Text(mgr.running ? "运行中" : "已停止").font(.headline)
            Spacer()
            Button(mgr.running ? "停止" : "启动") { mgr.toggle() }
                .buttonStyle(.borderedProminent)
                .tint(mgr.running ? .red : .green)
        }
        .padding()
    }

    var logPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(mgr.log.suffix(10), id: \.self) { line in
                    Text(line).font(.caption).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .frame(height: 60)
    }

    var bottomBar: some View {
        HStack {
            Button("配置") { mgr.revealConfig() }
                .buttonStyle(.link)
            Button("重置分类") {
                mgr.actionCategory = [:]
                mgr.saveKnownCategories()
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .font(.caption)
            Spacer()
            Text("\(mgr.localIP):\(String(mgr.config.port))")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.blue)
                .textSelection(.enabled)
        }
        .padding()
    }
}
