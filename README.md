# clash-auto-switch

当节点不可用时自动切换 clash 节点的定时脚本

支持设置两个优先级

## 使用方法

#### 运行你的 clash

####　编辑 clash-auto-switch.sh 文件

```bash
# 对应clash的external-controller，不要使用/结尾
api="http://127.0.0.1:9090"
# 对应clash的secret
token=
# 用于防止多个脚本同时执行，不理解使用默认路径即可
lockfilepath="/tmp/clash-check.lock"
# 优先选择的节点名称，此处为一个匹配关键词
# 这里会选择所有name中包含日本的节点，然后进行延迟测试，然后选择延迟最低的节点
firstProxy="日本"
# 次级选择节点的关键词，当首选关键词没有匹配到节点或所有节点不可用时，会使用该关键词再次匹配选择
secondProxy="IPLC"
# 一些简单的提示的输出，$1是内容
# 不会改默认即可
info(){
	# logger -s "$1" -t "clash-check-proxy" -p 6
	echo $1
}


# ....
```

#### 设置定时循环任务

```bash
# cron方式
# 1分钟执行一次
* * * * * /path/clash-auto-switch.sh
```

```bash
# bash方式
while true
do
  /path/clash-auto-switch.sh
  sleep 30s
done
```

两种方式二选一

别忘了给脚本添加执行权限

```bash
chmod +x /path/clash-auto-switch.sh
```

#### 依赖

- curl
- jq

#### 执行逻辑

首先判断当前正在使用的节点是否属于第一优先级节点

- 是:
  - 是否可用:
    - 是: 退出
    - 否: 寻找新节点
- 否: 寻找新节点
