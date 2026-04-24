# Cairn Probe

Phase 0 勘察脚本。扫描 `~/.claude/projects/` 下所有 JSONL 会话文件,
产出 `probe-report.md` 回答 spec 附录 B 的 10 个问题。

## 使用

```bash
pip install -r requirements.txt   # 安装 pytest
pytest test_probe.py -v           # 跑单测
python probe.py                   # 扫描真实数据,生成报告
```

## 输出

- `probe-report.md` — 结构化报告

## 为什么 Python 而非 Swift

- 一次性研究工具,未来 v1+ 不再维护
- Python 的 JSON / 字符串处理对 EDA 更方便
- 不污染 Swift 项目依赖

## 什么时候重跑

- Phase 0 初次勘察(本 milestone)
- Claude Code 大版本升级后(验证 JSONL 格式是否变化)
