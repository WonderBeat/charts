get_current_hour_jst() {
  utc_epoch=$(date +%s)
  jst_epoch=$((utc_epoch + 9 * 3600))
  date -u -d @"$jst_epoch" +%H
}

current_hour=$(get_current_hour_jst)

if [ "$current_hour" -gt 18 ] || [ "$current_hour" -lt 10 ]; then
  echo "Sleeping..."
  while true; do
    current_hour=$(get_current_hour_jst)
    if [ "$current_hour" -ge 10 ]; then
      break
    fi
    echo "sleeping... jst hour is $current_hour"
    sleep 30m
  done
fi

if [ $(($(date +%s) % 2)) -eq 0 ]; then
  printf "nameserver %s\nnameserver %s\n" "$DNS1" "$DNS2" >/etc/resolv.conf
else
  printf "nameserver %s\nnameserver %s\n" "$DNS2" "$DNS1" >/etc/resolv.conf
fi
echo "nameserver 10.46.0.10" >>/etc/resolv.conf # fallback

while true; do
  curl -q --max-time 10 --retry 5 --retry-delay 1 -f "https://proxy.webshare.io/api/v2/proxy/list/download/ojepfofzjjasrgwppcznvbecqlxmxoxtkhtcdznu/-/any/username/direct/" | tr ' ' '\n' | sed -E 's/^([0-9.]+):([0-9]+):([^:]+):([a-z0-9]+)/socks5:\/\/\3:\4@\1:\2/' >>/free-proxy.txt
  # printf "\n" >>/free-proxy.txt
  curl -q --max-time 10 --retry 5 --retry-delay 1 -f 'https://raw.githubusercontent.com/ErcinDedeoglu/proxies/refs/heads/main/proxies/socks4.txt' | tr ' ' '\n' | sed -E 's/^(.+)/socks4:\/\/\1/' >>/free-proxy.txt # printf "\n" >>/proxy.txt
  printf "\n" >>/free-proxy.txt
  curl -q --max-time 10 --retry 5 --retry-delay 1 -f 'https://raw.githubusercontent.com/monosans/proxy-list/refs/heads/main/proxies/socks5.txt' | tr ' ' '\n' | sed -E 's/^(.+)/socks5:\/\/\1/' >>/free-proxy.txt
  printf "\n" >>/free-proxy.txt
  curl -q --max-time 10 --retry 5 --retry-delay 1 -f 'https://raw.githubusercontent.com/monosans/proxy-list/refs/heads/main/proxies/socks4.txt' | tr ' ' '\n' | sed -E 's/^(.+)/socks4:\/\/\1/' >>/free-proxy.txt
  head -n 800 /free-proxy.txt >>/stage-proxy.txt
  socks_domain="socks-proxy-socks-proxy-server.trading.svc.cluster.local" # k8s proxy
  for ip in $(nslookup -query=A "$socks_domain" 10.46.0.10 | awk '/^Address: / {print $2}' | tail -n +2); do
    echo "socks5://$ip:1080" >>/stage-proxy.txt
  done
  echo "socks5://10.88.101.13:1080" >>/stage-proxy.txt # nas-duck
  echo "socks5://10.88.101.77:1080" >>/stage-proxy.txt # montenegro
  curl -q --max-time 10 --retry 5 --retry-delay 1 'https://api.best-proxies.ru/proxylist.txt?key=4660317f00a7da7d037b2b0d50d2f135&limit=600&type=http,socks4,socks5&includeType' >>/stage-proxy.txt
  shuf /stage-proxy.txt -o /proxy.txt
  sleep 10m
done &
while [ ! -s "/proxy.txt" ]; do
  echo -n "."
  sleep 5s
done

CHECK_URL="https://www.binance.$TLD/bapi/apex/v1/public/apex/cms/article/list/query?type=1&pageNo=0x1&pageSize=1&catalogId=0$CATALOG"
HEADERS="Accept:*/*"
HEADERS="$HEADERS,Accep-Language: en-US"
HEADERS="$HEADERS,Range: bytes=0-360"
HEADERS="$HEADERS,Accept-Encoding: gzip, deflate, br"
# HEADERS="$HEADERS,User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15) Gecko/20100101 Firefox/135.0"
# COOKIES="aws-waf-token=843559a3-16ea-4b4c-80d8-9f6ff256b9cd:CgoAn8Rug9wOAAAA:HvPLh37BjRgfNbNheWQaJYoGs4sJn0iI11TEuSP1JIUZYe17UIiJ2/B4pin7SeHNszBLtnrk+u4mMCfTjrlbymPdeQIjUY6/xt1Gxb0en1se3733ORqEZ2VfxcvGVt5fslLCmu0EcKi/hqxNl5ozUpXr0Tuk/YCKNyExfQSSDy2coe1BAUjMHsy+gCJjdeJHRzK3jBw="
# HEADERS="$HEADERS,Cookie: $COOKIES;"
echo "\n\nChecking $CHECK_URL"
while true; do
  timeout 5m mubeng -f proxy.txt -t 2s --check --output /checked.txt --check-url "$CHECK_URL" --check-url-content total --headers "$HEADERS"
  if [ -f "/checked.txt" ] && [ $(wc -l <"/checked.txt") -gt 4 ]; then
    mv /checked.txt /live.txt
    TOTAL=$(wc -l <proxy.txt)
    LIVE=$(wc -l <live.txt)
    echo "$TOTAL proxies checked. $LIVE is alive"
  fi
  sleep 7m
done &
until [ -f "/live.txt" ] && [ $(wc -l <"/live.txt") -gt 5 ]; do
  echo -n "."
  sleep 5s
done
timeout 2h mubeng -a 0.0.0.0:8000 --remove-on-error -t 3s -f /live.txt -w -min-alive 4
