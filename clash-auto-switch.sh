#!/bin/bash

source ./env

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
	echo `jq -nr --arg v "$1" '$v|@uri'`
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
	info "set proxy: $1 [$2ms]"
	curl --noproxy "*" -s -H "Authorization: Bearer $token" -X PUT  "$api/proxies/$selectorName" -d "{\"name\":\"$1\"}"
	if [ -e $recfilepath ];then
		rm $recfilepath
		whenRecovery "$1"
	fi
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
		setProxy "$minName" "$minDelay"
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
		echo "" > $recfilepath
		whenNotProxy
	fi
fi
unlock
