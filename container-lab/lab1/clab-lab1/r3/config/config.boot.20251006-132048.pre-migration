system {
    host-name r3
    login {
        user admin {
            authentication {
                plaintext-password "admin"
            }
            level admin
        }
    }
}
interfaces {
    ethernet eth1 {
        address 10.0.23.2/30
    }
}
service {
    ssh {
        port 22
    }
}
protocols {
    static {
        route 10.0.12.0/30 {
            next-hop 10.0.23.1 {
            }
        }
    }
}
