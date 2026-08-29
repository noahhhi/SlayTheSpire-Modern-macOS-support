#!/bin/bash
# Double-click entry point for the Universal modern macOS patch.
cd "$(dirname "$0")" || exit 1
./install.sh
rc=$?
echo
if [ "$rc" -eq 0 ]; then
  echo "Installation completed. / 安装完成。"
else
  echo "Installation failed (exit $rc). / 安装失败（退出码 $rc）。"
fi
read -r -p "Press Return to close / 按回车键关闭..."
exit "$rc"
