#!/bin/bash
api="http://127.0.0.1:9090"
token=
lockfilepath="/tmp/clash-check.lock"
firstProxy="日本"
secondProxy="IPLC"

info(){
	# logger -s "$1" -t "clash-check-proxy" -p 6
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
	curl --noproxy "*" -s -H "Authorization: Bearer $token" -X PUT  "$api/proxies/Proxy" -d "{\"name\":\"$1\"}"
}
getNowProxy(){
	echo `echo $1 | jq -r ".Proxy.now"`
}
isFirst(){
	local has=`echo "$1" | grep -c "$firstProxy"`
	if [ "$has" -eq 1 ];then
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
	info "当前为非[$firstProxy]代理"
fi

fProxy=`echo $proxies | jq -r ".Proxy.all" | grep -E "$firstProxy"`
fProxy=`echo $fProxy | sed s'/.$//'`
fProxy="[$fProxy]"
findProxyAndSet "$fProxy"
if [ 0 -ne "$?" ];then
	info "无可用[$firstProxy]线路"
	sProxy=`echo $proxies | jq -r ".Proxy.all" | grep -E "$secondProxy"`
	sProxy=`echo $sProxy | sed s'/.$//'`
	sProxy="[$sProxy]"
	findProxyAndSet "$sProxy"
	if [ 0 -eq "$?" ];then
		local newProxies=`gcurl /proxies | jq -r ".proxies"`
		local newNow=`getNowProxy "$newProxies"`
		info "无可用[$firstProxy]线路,切换到：$newNow"
	else
		info "无可用[$firstProxy]线路和[$secondProxy]线路"
	fi
fi
unlock
