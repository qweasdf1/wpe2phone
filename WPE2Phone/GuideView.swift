import SwiftUI

/// Step-by-step walkthrough for turning a saved Live Photo into the Lock Screen wallpaper.
struct GuideView: View {
    private let steps: [(icon: String, title: String, detail: String)] = [
        ("photo.on.rectangle", "打开「照片」App",
         "进入相册「WPE2Phone」，点开刚生成的实况照片"),
        ("square.and.arrow.up", "点左下角「分享」",
         "在分享菜单里选择「用作墙纸」"),
        ("circle.dotted.circle", "打开「实况」开关",
         "在预览页左下角点亮实况图标（虚线圆圈），没有斜杠才是开启"),
        ("checkmark.circle", "点「添加」完成",
         "选择「设为墙纸组合」或只设定锁定屏幕"),
        ("lock.iphone", "锁屏查看效果",
         "按电源键锁屏再点亮屏幕，壁纸就会自动播放")
    ]

    private let tips: [(icon: String, text: String)] = [
        ("battery.25", "低电量模式下不会播放动态效果，请关闭低电量模式"),
        ("figure.stand.line.dotted.figure.stand", "「设置 › 辅助功能 › 动态效果」中不要开启「减弱动态效果」"),
        ("video.slash", "片段晃动太剧烈时系统可能禁用动态效果，换一段画面更平稳的试试")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        StepBadge(number: index + 1)
                        VStack(alignment: .leading, spacing: 4) {
                            Label(step.title, systemImage: step.icon)
                                .font(.headline)
                            Text(step.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .cardStyle()
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("不动了？检查这三点", systemImage: "wrench.and.screwdriver")
                        .font(.headline)
                    ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                        Label(tip.text, systemImage: tip.icon)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .cardStyle()
            }
            .padding()
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("设为锁屏壁纸")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { GuideView() }
}
