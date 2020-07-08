#!/bin/bash -e

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi

compilers="crossbuild-essential-arm64 crossbuild-essential-armhf crossbuild-essential-armel gcc-arm-none-eabi"
dependencies="gnupg flex bison gperf build-essential zip curl libncurses5-dev zlib1g-dev \
parted kpartx debootstrap pixz qemu-user-static abootimg cgpt vboot-kernel-utils vboot-utils \
u-boot-tools bc lzma lzop automake autoconf m4 dosfstools rsync schedtool git dosfstools e2fsprogs \
device-tree-compiler libssl-dev systemd-container libgmp3-dev gawk qpdf make libfl-dev swig libpython2-dev \
python3-dev cgroup-tools lsof jetring"

deps="${dependencies} ${compilers}"

apt-wait () {
  while fuser /var/{lib/{dpkg,apt/lists},cache/apt/archives}/lock >/dev/null 2>&1; do
    sleep 5
  done

  if [ "$1" == "update" ];then
    apt-get update
  elif [ "$1" == "install" ];then
    apt-get -y -qq $@
  elif [ "$1" == "install_deps" ];then
    apt-get install -y -qq $deps
  elif [ "$1" == "remove" ];then
    apt-get -y --purge "$@"
  elif [ "$1" == "dpkg" ];then
    "$@"
  fi
}

apt-wait update
backup_packages=list-debs-$(date +"%H_%M_%m_%d_%Y")
dpkg --get-selections > ${backup_packages}
apt-wait install_deps

# Install kali-archive-keyring.
if [ ! -f /usr/share/keyrings/kali-archive-keyring.gpg ]; then
  temp_key="$(mktemp -d)"
  git clone https://gitlab.com/kalilinux/packages/kali-archive-keyring.git $temp_key
  cd $temp_key && make && make install && cd $OLDPWD && rm -rf $temp_key
fi

echo "Waiting for other software manager to finish..."

if [ $(arch) == 'x86_64' ]; then
  if [ -z $(dpkg --print-foreign-architectures|grep i386) ]; then
    dpkg --add-architecture i386
    apt-wait update
    deps="libstdc++6:i386 libc6:i386 libgcc1:i386 zlib1g:i386 libncurses5:i386"
    apt-wait install_deps
    del_arch_i386="dpkg --remove-architecture i386"
  elif [[ $(dpkg --print-foreign-architectures|grep i386) == 'i386' ]]; then
    deps="libstdc++6:i386 libc6:i386 libgcc1:i386 zlib1g:i386 libncurses5:i386"
    apt-wait install_deps
  fi
else
  deps="libncurses5"
  apt-wait install
fi

cat << EOF > clean_system${backup_packages//list-debs/}.sh
#!/bin/bash -e

clean_system () {
  dpkg --clear-selections
  dpkg --set-selections < ${backup_packages}
  apt-get -y dselect-upgrade
  apt-get -y remove --purge \$(dpkg -l | grep "^rc" | awk '{print \$2}')
  ${del_arch_i386}
}

clear
echo "Use this script under your responsibility"
read -p "Are you sure you want to remove the packages from the build? [y/n]: " yn
case \$yn in
  [Yy]* ) clean_system;;
  [Nn]* ) break;;
      * ) echo "Please enter Y or N!";;
esac
EOF
chmod 755 clean_system${backup_packages//list-debs/}.sh

# Function of changing from version number to full number.
versionToInt(){ local IFS=.;parts=($1);let val=1000000*parts[0]+1000*parts[1]+parts[2];echo $val;}

# Check minimum version debootstrap.
debootstrap_ver=$(versionToInt $(debootstrap --version |  grep -o '[0-9.]\+' | head -1))
debootstrap_min=$(versionToInt 1.0.105)

if [ ${debootstrap_ver} \< ${debootstrap_min} ]; then
  echo "Currently your version of debootstrap does not support the script."
  exit 1
fi
