import Foundation

/// 文件类型分类 — 决定文件是否可以在代码编辑器中打开。
///
/// 通过扩展名白名单 + 少量无扩展名文件名识别可编辑的文本/代码文件;
/// 其它所有文件统一归类为 `binary`(图片、PDF、媒体、压缩包、可执行文件等),
/// 不会尝试读取为文本,避免在编辑器里乱码或崩溃。
enum FileType {
    /// 可在代码编辑器中编辑的文本/代码文件。
    case text
    /// 不适合在文本编辑器中打开的二进制文件。
    case binary

    /// 扩展名白名单 — 列入其中的扩展名均视为可编辑的文本/代码文件。
    private static let textExtensions: Set<String> = [
        // 编程语言
        "swift", "kt", "kts", "java", "jav",
        "py", "pyi", "pyx", "ipynb",
        "js", "cjs", "mjs", "jsx",
        "ts", "cts", "mts", "tsx",
        "go", "rs",
        "c", "cc", "cpp", "cxx", "c++",
        "h", "hpp", "hxx",
        "m", "mm",
        "rb", "php",
        "sh", "bash", "zsh", "fish", "ps1", "bat", "cmd",
        "sql", "lua", "dart",
        "scala", "sbt",
        "clj", "cljs", "cljc",
        "r", "jl", "vim", "el",
        // 标记 / 数据
        "json", "json5", "yaml", "yml", "xml", "plist", "toml",
        "ini", "conf", "cfg", "properties", "env",
        // 文档
        "md", "markdown", "txt", "rst", "adoc", "tex",
        // Web
        "html", "htm", "shtml",
        "css", "scss", "sass", "less",
        "vue", "svelte",
        // 配置 / 脚本 / 补丁
        "gradle", "lock", "log", "diff", "patch",
    ]

    /// 无扩展名但可识别的常见文本文件名(小写比较)。
    private static let textFilenames: Set<String> = [
        "makefile", "dockerfile", "rakefile", "gemfile", "podfile",
        "vagrantfile", "procfile", "brewfile",
        ".bashrc", ".zshrc", ".profile", ".bash_profile", ".zprofile",
        ".gitignore", ".gitattributes", ".editorconfig",
        ".eslintrc", ".prettierrc",
        "license", "license.md", "license.txt",
        "readme", "readme.md", "readme.txt",
        "changelog", "changelog.md",
        "authors", "contributors",
    ]

    /// 判断给定的文件是否属于可在编辑器中打开的文本/代码文件。
    static func classify(_ url: URL) -> FileType {
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty {
            return textExtensions.contains(ext) ? .text : .binary
        }
        let name = url.lastPathComponent.lowercased()
        return textFilenames.contains(name) ? .text : .binary
    }

    /// 用户可读的文件类型名(用于「无法在编辑器中打开」占位视图)。
    static func displayName(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic", "svg", "ico"].contains(ext) {
            return "图片"
        }
        if ext == "pdf" { return "PDF 文档" }
        if ["mp4", "mov", "m4v", "avi", "mkv", "webm", "flv", "wmv", "mpeg", "mpg"].contains(ext) {
            return "视频"
        }
        if ["mp3", "wav", "m4a", "aac", "flac", "ogg", "wma", "opus"].contains(ext) {
            return "音频"
        }
        if ["zip", "tar", "gz", "tgz", "bz2", "bz", "7z", "rar", "xz", "zst", "lz4"].contains(ext) {
            return "压缩包"
        }
        if ["dmg", "iso", "pkg", "app", "exe", "msi", "deb", "rpm", "apk", "ipa",
            "dll", "so", "dylib"].contains(ext) {
            return "安装包 / 可执行文件"
        }
        if ["doc", "docx", "xls", "xlsx", "ppt", "pptx",
            "numbers", "key", "pages", "odt"].contains(ext) {
            return "Office 文档"
        }
        if ["ttf", "otf", "woff", "woff2", "eot"].contains(ext) {
            return "字体"
        }
        if ["key", "pem", "crt", "cer", "pub", "p12"].contains(ext) {
            return "密钥 / 证书"
        }
        return "二进制文件"
    }
}
