#!/bin/bash
LOG_TAG="5G-AUTO"

# 等待系统基本服务启动
sleep 20

# 1. 全自动识别5G模块串口
find_5g_serial() {
    logger -t $LOG_TAG "开始识别5G模块串口..."
    sleep 8
    SERIAL_PORTS=$(ls /dev/ttyUSB* 2>/dev/null)
    
    if [ -z "$SERIAL_PORTS" ]; then
        logger -t $LOG_TAG "错误：未找到USB串口设备！"
        return 1
    fi
    
    for PORT in $SERIAL_PORTS; do
        logger -t $LOG_TAG "验证串口：$PORT"
        if command -v microcom >/dev/null 2>&1; then
            AT_RESP=$(echo -e "AT+CGMI\r" | timeout 3 microcom -t 3000 $PORT 2>/dev/null | grep -i "quectel\|simcom\|fibocom\|meig")
        else
            stty -F $PORT 115200 >/dev/null 2>&1
            echo -e "AT+CGMI\r" > $PORT
            sleep 1
            AT_RESP=$(timeout 3 cat $PORT 2>/dev/null | grep -i "quectel\|simcom\|fibocom\|meig")
        fi
        
        if [ -n "$AT_RESP" ]; then
            logger -t $LOG_TAG "成功识别5G模块：$PORT"
            echo "$PORT"
            return 0
        fi
    done
    logger -t $LOG_TAG "错误：未找到有效5G模块串口！"
    return 1
}

# 2. 自动识别运营商APN
get_auto_apn() {
    logger -t $LOG_TAG "识别运营商..."
    for i in $(seq 1 15); do
        if mmcli -L 2>/dev/null | grep -q "modem"; then
            break
        fi
        sleep 2
    done
    
    MODEM_PATH=$(mmcli -L 2>/dev/null | grep -o "/org/freedesktop/ModemManager1/Modem/[0-9]*" | head -1)
    if [ -z "$MODEM_PATH" ]; then
        logger -t $LOG_TAG "使用默认APN: cmnet"
        echo "cmnet"
        return 0
    fi
    
    OPERATOR=$(mmcli -m $MODEM_PATH 2>/dev/null | grep "operator name" | cut -d: -f2 | tr -d ' ')
    if [ -n "$OPERATOR" ]; then
        logger -t $LOG_TAG "识别运营商：$OPERATOR"
        case "$OPERATOR" in
            *"China Mobile"*|*"中国移动"*) echo "cmnet";;
            *"China Unicom"*|*"中国联通"*) echo "3gnet";;
            *"China Telecom"*|*"中国电信"*) echo "ctnet";;
            *) echo "cmnet";;
        esac
        return 0
    fi
    
    echo "cmnet"
    logger -t $LOG_TAG "使用默认APN: cmnet"
    return 0
}

# 3. 5G拨号
start_5g_modem() {
    local AUTO_APN=$1
    logger -t $LOG_TAG "5G拨号（APN：$AUTO_APN）..."
    
    ifconfig wwan0 down 2>/dev/null
    pkill -f pppd 2>/dev/null
    
    # 使用uqmi拨号
    if [ -e "/dev/cdc-wdm0" ]; then
        logger -t $LOG_TAG "尝试QMI拨号..."
        uqmi -d /dev/cdc-wdm0 --stop-network 0xffffffff --autoconnect >/dev/null 2>&1
        uqmi -d /dev/cdc-wdm0 --set-data-format 802.3 >/dev/null 2>&1
        uqmi -d /dev/cdc-wdm0 --network-register >/dev/null 2>&1
        
        NETWORK_HANDLE=$(uqmi -d /dev/cdc-wdm0 --start-network "$AUTO_APN" --autoconnect)
        if [ $? -eq 0 ]; then
            if udhcpc -i wwan0 -q -f -n >/dev/null 2>&1; then
                WWAN_IP=$(ip addr show wwan0 2>/dev/null | grep "inet " | awk '{print $2}')
                if [ -n "$WWAN_IP" ]; then
                    logger -t $LOG_TAG "QMI拨号成功！IP: $WWAN_IP"
                    return 0
                fi
            fi
        fi
    fi
    
    # 备用PPP拨号
    SERIAL_PORT=$(find_5g_serial)
    if [ -n "$SERIAL_PORT" ]; then
        logger -t $LOG_TAG "尝试PPP拨号..."
        cat > /tmp/ppp-options << EOF
$SERIAL_PORT
115200
nocrtscts
modem
defaultroute
noipdefault
usepeerdns
noauth
persist
apn $AUTO_APN
EOF
        pppd file /tmp/ppp-options >/dev/null 2>&1 &
        
        for i in $(seq 1 20); do
            if ip route show default | grep -q ppp; then
                WWAN_IP=$(ip addr show ppp0 2>/dev/null | grep "inet " | awk '{print $2}')
                logger -t $LOG_TAG "PPP拨号成功！IP: $WWAN_IP"
                return 0
            fi
            sleep 2
        done
    fi
    
    logger -t $LOG_TAG "错误：5G拨号失败！"
    return 1
}

# 4. 网络转发配置
config_net_forward() {
    logger -t $LOG_TAG "配置网络转发..."
    echo 1 > /proc/sys/net/ipv4/ip_forward
    uci set network.wan.proto='dhcp'
    uci set network.wan.ifname='wwan0'
    uci commit network
    /etc/init.d/network reload
    iptables -t nat -A POSTROUTING -o wwan0 -j MASQUERADE
    logger -t $LOG_TAG "网络转发配置完成"
}

# 5. 主流程
main() {
    logger -t $LOG_TAG "===== 5G自动启动开始 ====="
    AUTO_APN=$(get_auto_apn)
    if start_5g_modem "$AUTO_APN"; then
        config_net_forward
        logger -t $LOG_TAG "===== 5G启动完成 ====="
        return 0
    else
        logger -t $LOG_TAG "===== 5G启动失败 ====="
        return 1
    fi
}

# 执行主函数
main
