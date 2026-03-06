import os
import re
from pathlib import Path


def export_code_structure(source_path, export_file_path, include_patterns=None, exclude_patterns=None, redaction_rules=None):
    source_path = Path(source_path).resolve()
    processed_files = []
    include_patterns = include_patterns or []
    exclude_patterns = exclude_patterns or []
    redaction_rules = redaction_rules or []

    def should_include(file_path):
        path_normalized = str(file_path).replace(os.sep, "/")

        if include_patterns:
            if not any(re.search(pattern, path_normalized) for pattern in include_patterns):
                return False

        if exclude_patterns:
            if any(re.search(pattern, path_normalized) for pattern in exclude_patterns):
                return False

        return True

    def build_tree(current_directory, relative_path=Path("."), prefix=""):
        lines = []
        try:
            items = sorted(
                [item for item in current_directory.iterdir() if should_include(relative_path / item.name) or item.is_dir()],
                key=lambda item: (not item.is_dir(), item.name.lower()),
            )
        except PermissionError:
            return lines

        for index, item in enumerate(items):
            is_last = index == len(items) - 1
            connector = "└── " if is_last else "├── "
            item_relative = relative_path / item.name

            if item.is_dir():
                subtree_lines = build_tree(item, item_relative, prefix + ("    " if is_last else "│   "))
                if subtree_lines:
                    lines.append(f"{prefix}{connector}📁 {item.name}/")
                    lines.extend(subtree_lines)
            else:
                if should_include(item_relative):
                    lines.append(f"{prefix}{connector}📄 {item.name}")
                    processed_files.append(item_relative)

        return lines

    tree_lines = [f"📁 {source_path.name}/"] + build_tree(source_path)

    with open(export_file_path, "w", encoding="utf-8") as file:
        file.write(f"# 目录结构\n{'-' * 80}\n\n")
        file.write("\n".join(tree_lines) + "\n\n")
        file.write(f"{'-' * 80}\n\n# 文件内容详情 (共 {len(processed_files)} 个文件)\n{'-' * 80}")

        for index, relative_path in enumerate(sorted(processed_files), 1):
            absolute_path = source_path / relative_path
            file.write(f"\n\n{'=' * 80}\n[{index}/{len(processed_files)}] {relative_path}\n大小: {absolute_path.stat().st_size} bytes\n{'=' * 80}\n\n")

            try:
                content = absolute_path.read_text(encoding="utf-8", errors="ignore")
                for pattern, replacement in redaction_rules:
                    content = re.sub(pattern, replacement, content)
                file.write(content)
            except Exception as error:
                file.write(f"[读取错误: {str(error)}]")

    print(f"✅ 导出完成！已保存到: {export_file_path}")


if __name__ == "__main__":
    export_code_structure(
        source_path=r".",
        export_file_path="./code_export.txt",
        include_patterns=[
            r"\.py$",
        ],
        redaction_rules=[
            (r"(\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b)", "[IP_ADDRESS]"),
            (r"(?i)([a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,})", "[EMAIL]"),
            (r"(?i)\b[a-f0-9]{32,128}\b", "[HEX_KEY]"),
            (r'(?i)(password\s*=\s*)("[^"]*"|\'[^\']*\'|[a-z0-9]{8,512})', r"\1[PASSWORD]"),
            (r'(?i)(secret\s*=\s*)("[^"]*"|\'[^\']*\'|[a-z0-9]{8,512})', r"\1[SECRET]"),
            (r'(?i)(token\s*=\s*)("[^"]*"|\'[^\']*\'|[a-z0-9]{8,512})', r"\1[TOKEN]"),
            (r'(?i)(key\s*=\s*)("[^"]*"|\'[^\']*\'|[a-z0-9]{8,512})', r"\1[KEY]"),
            (r'(?i)(api[_-]?key\s*=\s*)("[^"]*"|\'[^\']*\'|[a-z0-9]{8,512})', r"\1[API_KEY]"),
            (r"(?i)(sk-[a-z0-9]{48})", "[OPENAI_API_KEY]"),
        ],
    )
