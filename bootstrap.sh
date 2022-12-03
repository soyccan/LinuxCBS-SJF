#!/bin/bash

function download_cloud_image() {
    wget 'https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img'
    wget 'https://cloud-images.ubuntu.com/jammy/current/SHA256SUMS.gpg'
    wget 'https://cloud-images.ubuntu.com/jammy/current/SHA256SUMS'

    # Ubuntu Cloud Image Builder (Canonical Internal Cloud Image Builder) <ubuntu-cloudbuilder-noreply@canonical.com>
    gpg --keyserver pgp.mit.edu --recv 7FF3F408476CF100
    gpg --verify SHA256SUMS.gpg SHA256SUMS
    sha256sum --check --ignore-missing SHA256SUMS
}

function pack_initramfs() {
    (
        cd initramfs || return
        find . -print0 | cpio --null -ov --format=newc > ../initramfs.cpio
    )
}

function replicate_cloud_image() {
    cp -f jammy-server-cloudimg-amd64.img jammy-server-cloudimg-amd64.qcow2
    qemu-img resize jammy-server-cloudimg-amd64.qcow2 +10G
}

function create_user_data_disk() {
    cloud-localds -v cloud.img cloud.yaml
}

function create_video_disk() {
    sudo virt-make-fs -F qcow2 -t ext4 videos videos.qcow2
    sudo chown soyccan:soyccan videos.qcow2
}

function boot_ubuntu_cloud() {
    sudo qemu-system-x86_64 \
        -m 1G \
        -kernel linux/arch/x86/boot/bzImage \
        -initrd initramfs.cpio \
        -append "console=ttyS0" \
        -device virtio-blk-pci,id=vd0,drive=drive0,num-queues=4 \
            -drive file=jammy-server-cloudimg-amd64.qcow2,format=qcow2,if=none,id=drive0 \
        -device virtio-blk-pci,id=vd1,drive=drive1,num-queues=4 \
            -drive file=cloud.img,format=raw,if=none,id=drive1 \
        -device virtio-blk-pci,id=vd2,drive=drive2,num-queues=4 \
            -drive file=videos.qcow2,format=qcow2,if=none,id=drive2 \
        -device virtio-net-pci,netdev=net0 \
        -netdev user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22 \
        -nographic \
        -enable-kvm \
        -s
        # -smp 24,sockets=1,cores=12,threads=2 \
        # -snapshot \
}

function ssh_connect() {
    ssh-keygen -R "[localhost]:2222"
    ssh soyccan@localhost -p 2222 -o StrictHostKeyChecking=no
}

if [[ "$1" ]] && typeset -F "$1"; then
    eval "$1"
else
    boot_ubuntu_cloud
fi

