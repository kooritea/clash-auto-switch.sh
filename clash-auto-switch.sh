#!/bin/bash

basepath=$(cd `dirname $0`; pwd)
source "$basepath/env"

lock(){
	echo "" > $lockfilepath
}
unlock(){
	rm $lockfilepath
}
urlencode() {
	echo `jq -nr --arg v "$1" '$v|@uri'`
}

ping(){
	local encodename=`urlencode "$1"`
	local data=`gcurl "/proxies/$encodename/delay?timeout=2000&url=http:%2F%2Fwww.gstatic.com%2Fgenerate_204"`
	local delay=`echo $data | jq -r ".delay"`
	echo $delay
}
gcurl(){
	echo `curl --noproxy "*" -s -H "Authorization: Bearer $token"  "${api}${1}"`
}

setProxy(){
	info "set proxy: $1 [$2ms]"
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
testProxyName(){
	#$2.test($1)
	local has=`echo "$1" | grep -c "$2"`
	if [ "$has" -ne 0 ];then
		#匹配失败
		return 0
	else
		return 1
	fi
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

if [ -e $lockfilepath ];then
	exit 0
fi
lock

proxies=`gcurl /proxies | jq -r ".proxies"`
nowProxy=`getNowProxy "$proxies"`
nowdelay=`ping "$nowProxy"`
testProxyName "$nowProxy" ${selectProxyRule[0]}

if [ 0 -eq $? ];then
	if [ "null" != "$nowdelay" ];then
		unlock
		exit 0
	else
		info "当前代理[$nowProxy]不可用"
	fi
else
	info "当前为非[${selectProxyRule[0]}]代理: [$nowProxy][$nowdelay]"
fi

Proxys=`echo $proxies | jq -r ".$selectorName.all"`

for item in ${selectProxyRule[*]};do

	testProxyName "$nowProxy" "$item"
	if [ 0 -eq $? ];then
		nowdelay=`ping "$nowProxy"`
		if [ "null" != "$nowdelay" ];then
		# 当前已是次级代理且可用
		info "当前已是代理[$item]且可用: [$nowProxy][$nowdelay]"
		unlock
		exit 0
		fi
	fi
	matchProxys=`match "$item" "$Proxys"`
	echo "$matchProxys"
	findProxyAndSet "$matchProxys"
	if [ 0 -eq "$?" ];then
		if [ -e $recfilepath ];then
			rm $recfilepath
			whenRecovery "$1"
		fi
		unlock
		exit 0
	else
		info "无可用[$item]线路"
	fi
done

if [ ! -e $recfilepath ];then
	echo "" > $recfilepath
	whenNotProxy
fi
unlock
exit 0