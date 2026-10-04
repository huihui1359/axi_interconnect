# Repository Documentation Rules

## Versioned Markdown Header

新建或实质更新本仓库中的规格、架构、微架构、验证计划、testbench plan、设计说明和评审报告等 Markdown 文档时，文档必须以以下 header 开头：

```markdown
# <Document Title>

**Author**: <human author or ?>, <tool author>, <exact model name or ?>
**Created**: YYYY-MM-DD HH:MM
**Current Version**: v<major>.<minor>

**Version Changelog**:
- **v<major>.<minor>** (YYYY-MM-DD HH:MM): <change summary>

---
```

执行规则：

- Header 必须紧跟唯一的一级标题，并位于正文第一节之前；字段名称、顺序和 Markdown 形式保持一致。
- 时间使用项目本地时区 `Asia/Shanghai`，格式固定为 `YYYY-MM-DD HH:MM`。
- 新文档从 `v1.0` 开始。后续实质修改必须更新 `Current Version`，并在 changelog 顶部添加同版本记录；最新记录在最上方。
- 保留最初的 `Created` 值，不得在后续编辑中改写。若旧文档缺少 header，应优先从可靠的版本历史或文件记录恢复创建时间；无法确认时使用补录时间，并在 changelog 中说明。
- `Author` 依次写有依据的人类作者、工具作者和精确模型名，例如 `Wang Jianghao, Codex, GPT-5.6-Solar`。模型名必须精确到具体变体，不得只写 `GPT-5.6`、`GPT-5` 或泛称 AI。
- 无法从用户说明、已有 header、版本历史或其他可靠项目记录确认人类作者或模型时，在对应位置写 `?`，例如 `?, Codex, ?`；不得臆测。交付结果必须主动列出所有 `?` 并提示用户补全。
- Changelog 摘要应说明本版本的实质变化和范围，不使用“更新文档”等无信息描述。
- 纯排版、拼写修复可不升版本；一旦修改需求、接口、行为、验证策略、pass criteria、coverage 或实现计划，就必须升版本并记录。
