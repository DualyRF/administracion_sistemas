sudo tee /etc/pam.d/vsftpd << 'EOF'
auth     required    pam_unix.so     shadow nullok
account  required    pam_unix.so
session  required    pam_unix.so
EOF