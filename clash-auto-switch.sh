#!/bin/bash
api="http://127.0.0.1:9090"
token=
lockfilepath="/tmp/clash-check.lock"

#代理选择器的项名，脚本只会检查这一项并切换
#clash的config.yaml里面Proxy Group项的name
#只能是英文，如果有中文请先使用sed命令替换
#cat ./config.yaml | sed 's/国外流量/proxy/' > ./config.yaml
selectorName="proxy"

# 优先选择的节点名称，此处为一个匹配关键词
firstProxy=("日本" "3.0|1.0")

# 次级选择节点的关键词，当首选关键词没有匹配到节点或所有节点不可用时，会使用该关键词再次匹配选择
secondProxy=("IPLC|5.0")

#firstProxy和secondProxy的语法规则
# 使用|符号,只需匹配[IPLC]和[5.0]其中一个关键词
# 使用空格，则同时匹配[日本]和[3.0|1.0]两个关键词的节点，然后进行延迟测试，然后选择延迟最低的节点

info(){
	#logger -s "$1" -t "clash-check-proxy" -p 6
	echo $1
}

lock(){
	echo "" > $lockfilepath
}
unlock(){
	rm $lockfilepath
}
if [ -e $lockfilepath ];then
	exit 0
fi
lock
urlencode() {
	local data=`jq -nr --arg v "$1" '$v|@uri'`
	echo $data | sed "s/%5D/]/g" |  sed "s/%5B/[/g"
}

ping(){
	local encodename=`urlencode "$1"`
	local data=`gcurl "/proxies/$encodename/delay?timeout=5000&url=http:%2F%2Fwww.gstatic.com%2Fgenerate_204"`
	local delay=`echo $data | jq -r ".delay"`
	echo $delay
}
gcurl(){
	echo `curl --noproxy "*" -s -H "Authorization: Bearer $token"  "${api}${1}"`
}

setProxy(){
	info "set proxy: $1"
	curl --noproxy "*" -s -H "Authorization: Bearer $token" -X PUT  "$api/proxies/$selectorName" -d "{\"name\":\"$1\"}"
}
getNowProxy(){
	echo `echo $1 | jq -r ".$selectorName.now"`
}
match(){
	local arr="$1"
	local result="$2"
	for item in ${arr[*]};do
		result=`echo $result | jq | grep -E "$item"`
		result=`echo $result | sed s'/,$//'`
		result="[$result]"
	done
	echo $result
}
isFirst(){
	local has
	for item in ${firstProxy[*]};do
		has=`echo $1 | grep -c "$item"`
		if [ "$has" -ne 1 ];then
			return 1
		fi	
	done
	return 0
}
findProxyAndSet(){
	local minDelay=9999
	local minName="null"
	local count=`echo $1 | jq -c -r '.[]' | grep -c .`
	count=$(($count-1))
	for i in `seq $count -1 1`  
	do
   	local name=`echo $1 | jq -c -r ".[$i]"`
		local encodename=`urlencode "$name"`
		local delay=`ping "$name"`
		if [ "$delay" != "null" ];then
			if [ "$minDelay" -gt "$delay" ];then
				minDelay=$delay
				minName=$name
			fi
		fi
	done
	if [ "$minName" != "null" ];then
		setProxy "$minName"
		return 0
	else
		return 1
	fi
}


proxies=`gcurl /proxies | jq -r ".proxies"`
nowProxy=`getNowProxy "$proxies"`
nowdelay=`ping "$nowProxy"`
isFirst "$nowProxy"
if [ 0 -eq $? ];then
	if [ "null" != "$nowdelay" ];then
		unlock
		exit 0
	else
		info "当前代理不可用"
	fi
else
	info "当前为非[${firstProxy[*]}]代理"
fi

fProxy=`echo $proxies | jq -r ".$selectorName.all"`
fProxy=`match "${firstProxy[*]}" "$fProxy"`

findProxyAndSet "$fProxy"
if [ 0 -ne "$?" ];then
	info "无可用[${firstProxy[*]}]线路"
	
	isFirst "$nowProxy"
	if [ 0 -ne $? ];then
		# 当前已经是次选代理
		if [ "null" != "$nowdelay" ];then
			unlock
			exit 0
		fi
	fi

	#搜索次选代理
	sProxy=`echo $proxies | jq -r ".$selectorName.all"`
	sProxy=`match "${secondProxy[*]}" "$sProxy"`
	findProxyAndSet "$sProxy"
	if [ 0 -eq "$?" ];then
		newProxies=`gcurl /proxies | jq -r ".proxies"`
		newNow=`getNowProxy "$newProxies"`
		info "无可用[${firstProxy[*]}]线路,切换到：$newNow"
	else
		info "无可用[${firstProxy[*]}]线路和[${secondProxy[*]}]线路"
	fi
fi
unlock