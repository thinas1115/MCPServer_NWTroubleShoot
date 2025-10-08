interfaces {
}
service {
    ssh {
        port "22"
    }
}
system {
    host-name "r1"
    login {
        user admin {
            authentication {
                encrypted-password "$6$rounds=656000$BQ1.cVKRLHhojVlF$F1dJ6eQXwjMsM7cCav5DxGXqA8okHj58KVPVgBXGKegayDvr9RGNEceB4OhmPU0Cjbz9OkLCmSijwf9xQwx/60"
            }
        }
    }
}


// Warning: Do not remove the following line.
// vyos-config-version: "bgp@8:broadcast-relay@1:cluster@2:config-management@1:conntrack@6:conntrack-sync@2:container@3:dhcp-relay@2:dhcp-server@11:dhcpv6-server@6:dns-dynamic@4:dns-forwarding@4:firewall@20:flow-accounting@3:https@7:ids@2:interfaces@34:ipoe-server@4:ipsec@13:isis@3:l2tp@9:lldp@3:mdns@1:monitoring@2:nat@8:nat66@3:nhrp@1:ntp@3:openconnect@3:openvpn@4:ospf@2:pim@1:policy@9:pppoe-server@11:pptp@5:qos@3:quagga@12:reverse-proxy@3:rip@1:rpki@2:salt@1:snmp@3:ssh@2:sstp@6:system@29:vpp@1:vrf@3:vrrp@4:vyos-accel-ppp@2:wanloadbalance@4:webproxy@2"
// Release version: 2025.10.01-0021-rolling
