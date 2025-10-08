system {
    host-name r1
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
        address 10.0.12.1/30
    }
}
service {
    ssh {
        port 22
    }
}
