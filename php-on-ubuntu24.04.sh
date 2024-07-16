apt update && apt upgrade -y
echo 'APT::Key::Assert-Pubkey-Algo "";' | sudo tee /etc/apt/apt.conf.d/99weakkey-warning
apt update -y

#apt update && apt upgrade -y && echo 'APT::Key::Assert-Pubkey-Algo "";' | sudo tee /etc/apt/apt.conf.d/99weakkey-warning && apt update -y &&  add-apt-repository ppa:ondrej/php -y && apt install apache2 && apt install php8.1 php8.1-common php8.1-curl php8.1-mysql php8.1-xml php8.1-mbstring  php8.1-zip  php8.1-bcmath  php8.1-gd  php8.1-intl php8.1-imap  php-imagick php-ssh2 php8.1-fpm libapache2-mod-fcgid -y &&  a2enmod proxy_fcgi setenvif && a2enconf php8.1-fpm && apt install curl apt-transport-https software-properties-common lsb-release ca-certificates gnupg2 -y
