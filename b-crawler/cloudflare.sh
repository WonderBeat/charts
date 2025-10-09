# get_current_hour_jst() {
#   utc_epoch=$(date +%s)
#   jst_epoch=$((utc_epoch + 9 * 3600))
#   date -u -d @"$jst_epoch" +%H
# }
#
# current_hour=$(get_current_hour_jst)
#
# if [ "$current_hour" -gt 17 ] || [ "$current_hour" -lt 9 ]; then
#   echo "Sleeping..."
#   while true; do
#     current_hour=$(get_current_hour_jst)
#     if [ "$current_hour" -ge 9 ]; then
#       break
#     fi
#     echo "sleeping... jst hour is $current_hour"
#     sleep 30m
#   done
# fi

# DNS not required cuz Cloudflare uses unicast
#echo "nameserver 10.46.0.10" >/etc/resolv.conf # fallback

./main.py
