from __future__ import annotations

import ast
import json
import os
import sys
from dataclasses import asdict, dataclass
from pathlib import Path


EXCLUDED_DIRECTORIES = {
    ".git",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".tox",
    ".venv",
    "__pycache__",
    "build",
    "dist",
    "env",
    "node_modules",
    "venv",
}


@dataclass
class MethodRecord:
    name: str
    line: int
    start_line: int
    end_line: int
    column: int
    abstract: bool


@dataclass
class BaseRecord:
    name: str
    line: int
    end_line: int
    column: int
    end_column: int
    resolved_id: str | None


@dataclass
class ClassRecord:
    id: str
    name: str
    qualname: str
    module: str
    filename: str
    line: int
    end_line: int
    column: int
    raw_bases: list[str]
    bases: list[BaseRecord]
    base_ids: list[str]
    methods: list[MethodRecord]


def module_name_for(relative_file: Path) -> tuple[str, bool]:
    module_parts = list(relative_file.with_suffix("").parts)
    is_package = bool(module_parts and module_parts[-1] == "__init__")
    if is_package:
        del module_parts[-1]
    return ".".join(module_parts), is_package


def dotted_expression(expression: ast.expr) -> str | None:
    if isinstance(expression, ast.Name):
        return expression.id
    if isinstance(expression, ast.Attribute):
        owner_name = dotted_expression(expression.value)
        return f"{owner_name}.{expression.attr}" if owner_name else expression.attr
    if isinstance(expression, ast.Subscript):
        return dotted_expression(expression.value)
    if isinstance(expression, ast.Call):
        return dotted_expression(expression.func)
    return None


def decorator_name(decorator: ast.expr) -> str | None:
    decorated_expression = decorator.func if isinstance(decorator, ast.Call) else decorator
    return dotted_expression(decorated_expression)


def import_aliases(
    module_document: ast.Module,
    module_name: str,
    is_package: bool,
) -> dict[str, str]:
    aliases: dict[str, str] = {}
    current_package = module_name if is_package else module_name.rpartition(".")[0]
    package_parts = current_package.split(".") if current_package else []
    for node in ast.walk(module_document):
        if isinstance(node, ast.Import):
            for imported_name in node.names:
                local_name = imported_name.asname or imported_name.name.split(".")[0]
                aliases[local_name] = imported_name.name
        elif isinstance(node, ast.ImportFrom):
            retained_count = max(0, len(package_parts) - max(0, node.level - 1))
            retained_package = package_parts[:retained_count]
            imported_module_parts = node.module.split(".") if node.module else []
            absolute_module = ".".join(retained_package + imported_module_parts)
            for imported_name in node.names:
                if imported_name.name == "*":
                    continue
                local_name = imported_name.asname or imported_name.name
                aliases[local_name] = ".".join(
                    part for part in (absolute_module, imported_name.name) if part
                )
    return aliases


class ClassCollector:
    def __init__(
        self,
        module_name: str,
        filename: Path,
    ) -> None:
        self.module_name: str = module_name
        self.filename: Path = filename
        self.class_names: list[str] = []
        self.classes: list[ClassRecord] = []

    def collect(self, module_document: ast.Module) -> None:
        self._visit_node(module_document)

    def _visit_node(self, node: ast.AST) -> None:
        if isinstance(node, ast.ClassDef):
            self._collect_class(node)
            return
        for child_node in ast.iter_child_nodes(node):
            self._visit_node(child_node)

    def _collect_class(self, node: ast.ClassDef) -> None:
        qualified_parts = self.class_names + [node.name]
        qualname = ".".join(qualified_parts)
        full_name = ".".join(part for part in (self.module_name, qualname) if part)
        raw_bases = [
            base_name
            for base_expression in node.bases
            if (base_name := dotted_expression(base_expression)) is not None
        ]
        bases = [
            BaseRecord(
                name=base_name,
                line=base_expression.lineno,
                end_line=base_expression.end_lineno or base_expression.lineno,
                column=base_expression.col_offset + 1,
                end_column=(base_expression.end_col_offset or base_expression.col_offset) + 1,
                resolved_id=None,
            )
            for base_expression in node.bases
            if (base_name := dotted_expression(base_expression)) is not None
        ]
        methods: list[MethodRecord] = []
        for statement in node.body:
            if isinstance(statement, (ast.FunctionDef, ast.AsyncFunctionDef)):
                decorator_lines = [
                    decorator.lineno for decorator in statement.decorator_list
                ]
                start_line = min(decorator_lines + [statement.lineno])
                methods.append(
                    MethodRecord(
                        name=statement.name,
                        line=statement.lineno,
                        start_line=start_line,
                        end_line=statement.end_lineno or statement.lineno,
                        column=statement.col_offset + 1,
                        abstract=any(
                            (decorated_name := decorator_name(decorator)) is not None
                            and decorated_name.rsplit(".", 1)[-1] == "abstractmethod"
                            for decorator in statement.decorator_list
                        ),
                    )
                )
        self.classes.append(
            ClassRecord(
                id=f"{self.filename}:{node.lineno}:{full_name}",
                name=node.name,
                qualname=qualname,
                module=self.module_name,
                filename=str(self.filename),
                line=node.lineno,
                end_line=node.end_lineno or node.lineno,
                column=node.col_offset + len("class ") + 1,
                raw_bases=raw_bases,
                bases=bases,
                base_ids=[],
                methods=methods,
            )
        )
        self.class_names.append(node.name)
        for child_node in ast.iter_child_nodes(node):
            self._visit_node(child_node)
        del self.class_names[-1]


def candidate_base_names(
    class_record: ClassRecord,
    raw_base: str,
    aliases_by_module: dict[str, dict[str, str]],
) -> list[str]:
    base_parts = raw_base.split(".")
    module_aliases = aliases_by_module.get(class_record.module, {})
    imported_name = module_aliases.get(base_parts[0])
    expanded_import = (
        ".".join([imported_name] + base_parts[1:]) if imported_name else None
    )
    enclosing_parts = class_record.qualname.split(".")[:-1]
    local_qualified_name = ".".join(
        part
        for part in (class_record.module, *enclosing_parts, raw_base)
        if part
    )
    module_qualified_name = ".".join(
        part for part in (class_record.module, raw_base) if part
    )
    return [
        candidate
        for candidate in (
            expanded_import,
            local_qualified_name,
            module_qualified_name,
            raw_base,
        )
        if candidate
    ]


def resolve_base_ids(
    classes: list[ClassRecord],
    aliases_by_module: dict[str, dict[str, str]],
) -> None:
    classes_by_full_name: dict[str, list[ClassRecord]] = {}
    classes_by_leaf_name: dict[str, list[ClassRecord]] = {}
    for class_record in classes:
        full_name = ".".join(
            part for part in (class_record.module, class_record.qualname) if part
        )
        classes_by_full_name.setdefault(full_name, []).append(class_record)
        classes_by_leaf_name.setdefault(class_record.name, []).append(class_record)

    for class_record in classes:
        resolved_ids: list[str] = []
        for base_record in class_record.bases:
            raw_base = base_record.name
            resolved_class: ClassRecord | None = None
            for candidate_name in candidate_base_names(
                class_record,
                raw_base,
                aliases_by_module,
            ):
                matching_classes = classes_by_full_name.get(candidate_name, [])
                if len(matching_classes) == 1:
                    resolved_class = matching_classes[0]
                    break
            if resolved_class is None:
                leaf_matches = classes_by_leaf_name.get(raw_base.rsplit(".", 1)[-1], [])
                if len(leaf_matches) == 1:
                    resolved_class = leaf_matches[0]
            if resolved_class and resolved_class.id not in resolved_ids:
                resolved_ids.append(resolved_class.id)
                base_record.resolved_id = resolved_class.id
        class_record.base_ids.extend(resolved_ids)


def index_project(root_directory: Path) -> dict[str, object]:
    classes: list[ClassRecord] = []
    aliases_by_module: dict[str, dict[str, str]] = {}
    python_files: list[Path] = []
    for directory_path, directory_names, file_names in os.walk(root_directory):
        directory_names[:] = sorted(
            directory_name
            for directory_name in directory_names
            if directory_name not in EXCLUDED_DIRECTORIES
        )
        for file_name in sorted(file_names):
            if file_name.endswith(".py"):
                python_files.append(Path(directory_path, file_name))
    for python_file in python_files:
        try:
            source = python_file.read_text(encoding="utf-8")
            module_document = ast.parse(source, filename=str(python_file))
        except (OSError, SyntaxError, UnicodeDecodeError):
            continue
        relative_file = python_file.relative_to(root_directory)
        module_name, is_package = module_name_for(relative_file)
        aliases = import_aliases(module_document, module_name, is_package)
        aliases_by_module[module_name] = aliases
        collector = ClassCollector(module_name, python_file.resolve())
        collector.collect(module_document)
        classes.extend(collector.classes)

    resolve_base_ids(classes, aliases_by_module)
    return {"classes": [asdict(class_record) for class_record in classes]}


def main(arguments: list[str]) -> int:
    if len(arguments) != 2:
        print("usage: python_hierarchy_index.py ROOT", file=sys.stderr)
        return 2
    root_directory = Path(arguments[1]).expanduser().resolve()
    print(json.dumps(index_project(root_directory), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
