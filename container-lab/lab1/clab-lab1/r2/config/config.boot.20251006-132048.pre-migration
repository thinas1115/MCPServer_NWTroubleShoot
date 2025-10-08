system {
    host-name r2
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
        address 10.0.12.2/30
    }
    ethernet eth2 {
        address 10.0.23.1/30
    }
}
service {
    ssh {
        port 22
    }
}
