#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

public_file=/www/server/panel/install/public.sh
. $public_file
publicFileMd5=$(md5sum ${public_file} 2>/dev/null|awk '{print $1}')
md5check="484c945780dc4a802cff267f3fb15a66"
if [ "${publicFileMd5}" != "${md5check}"  ] && [ -z "${NODE_URL}" ]; then
	wget -O Tpublic.sh https://download.bt.cn/install/public.sh -T 20;
	publicFileMd5=$(md5sum Tpublic.sh 2>/dev/null|awk '{print $1}')
	if [ "${publicFileMd5}" == "${md5check}"  ]; then
		\cp -rpa Tpublic.sh $public_file
	fi
	rm -f Tpublic.sh
	. $public_file
fi
if [ -z "${cpuCore}" ]; then
	cpuCore="1"
fi

download_Url=$NODE_URL

Root_Path=`cat /var/bt_setupPath.conf`
Setup_Path=$Root_Path/server/php
php_path=$Root_Path/server/php
mysql_dir=$Root_Path/server/mysql
mysql_config="${mysql_dir}/bin/mysql_config"
Is_64bit=`getconf LONG_BIT`
run_path='/root'
apacheVersion=`cat /var/bt_apacheVersion.pl`
aarch64Check=$(uname -a|grep aarch64)
Get_Sys_Version(){
	if [ -f "/etc/os-release" ];then
		. /etc/os-release
		OS_V=${VERSION_ID%%.*}
		if [ "${ID}" == "debian" ] && [[ "${OS_V}" =~ ^(10|11|12|13)$ ]];then
			OS_NAME=${ID}
		elif [ "${ID}" == "ubuntu" ] && [[ "${OS_V}" =~ ^(20|22|24|26)$ ]];then
			OS_NAME=${ID}
		elif [ "${ID}" == "centos" ] && [[ "${OS_V}" =~ ^(7|8|9|10)$ ]];then
			OS_NAME="el"
		elif [ "${ID}" == "opencloudos" ] && [[ "${OS_V}" =~ ^(9)$ ]];then
			OS_NAME=${ID}
		elif [ "${ID}" == "alinux" ] && [[ "${OS_V}" =~ ^(3|4)$ ]];then
		    OS_NAME=${ID}
		elif [ "${ID}" == "alios" ] && [[ "${OS_V}" =~ ^(8)$ ]];then
		    OS_NAME=${ID}
		elif [ "${ID}" == "ol" ] && [[ "${OS_V}" =~ ^(9)$ ]];then
		 	OS_NAME=${ID}
		elif [ "${ID}" == "hce" ] && [[ "${OS_V}" =~ ^(2)$ ]];then
		    OS_NAME=${ID}
		elif [ "${ID}" == "tencentos" ] && [[ "${OS_V}" =~ ^(4)$ ]];then
		    OS_NAME=${ID}
 		elif { [ "${ID}" == "almalinux" ] || [ "${ID}" == "centos" ] || [ "${ID}" == "rocky" ]; } && [[ "${OS_V}" =~ ^(8|9|10)$ ]]; then
		    OS_NAME="el"
		fi
	fi
    X86_CHECK=$(uname -m|grep x86_64)
}
limit_check(){
    if [ "${version}" == "5.2" ] || [ "${apacheVersion}" == "2.2" ];then
        wget -O php.sh $download_Url/install/0/old/php.sh -T 5
        bash php.sh  $actionType $version
        exit;
    fi

    loongarch64Check=$(uname -a|grep loongarch64)
    if [ "${loongarch64Check}" ];then
        wget -O php.sh ${download_Url}/install/0/loongarch64/php.sh && sh php.sh $actionType $version
        exit;
    fi

    if [ -z "${OS_NAME}" ] || [ -z "${X86_CHECK}" ];then
        wget -O php.sh ${download_Url}/install/4/old/php.sh && sh php.sh $actionType $version
        exit
    fi

	if [ $OS_V == 20 ] && [ "${OS_NAME}" == "ubuntu" ]; then
		if [ "${version}" != "8.4" ] && [ "${version}" != "7.4" ];then
			wget -O php.sh ${download_Url}/install/4/old/php.sh && sh php.sh $actionType $version
        	exit
		fi 
	fi
}
Error_Msg(){
	if [ "${actionType}" == "install" ];then
		AC_TYPE="安装"
	elif [ "${actionType}" == "update" ]; then
		AC_TYPE="升级"
	fi

	EN_CHECK=$(cat /www/server/panel/config/config.json |grep English)
	echo '========================================================'
	GetSysInfo
	echo -e "ERROR: php-${phpVersion} ${actionType} failed.";
	if [ "${EN_CHECK}" ];then
		echo -e "Please submit to https://forum.aapanel.com for help"
	else
	    if [ -z "${SYS_VERSION}" ];then
            echo -e "============================================"
            echo -e "检测到为非常用系统安装,请尝试安装其他php版本看是否正常"
            echo -e "如无法正常安装，建议更换至Centos-7或Debian-11+或Ubuntu-20+系统安装宝塔面板"
            echo -e "详情请查看系统兼容表：https://docs.qq.com/sheet/DUm54VUtyTVNlc21H?tab=BB08J2"
            echo -e "特殊情况可通过以下联系方式寻求安装协助情况"
            echo -e "============================================"
        fi 
		echo -e "${AC_TYPE}失败，请截图以上报错信息发帖至论坛www.bt.cn/bbs求助"
	fi
	exit 1;
}
MD5_check(){
    \cp -rpa /www/server/php/${php_version}/bin/php /www/backup/php${php_version}.Bak
    \cp -rpa /www/server/php/${php_version}/sbin/php-fpm /www/backup/php-fpm${php_version}.Bak
    chmod -x /www/backup/php${php_version}.Bak
    chmod -x /www/backup/php-fpm${php_version}.Bak
    md5sum /www/server/php/${php_version}/bin/php > /www/server/panel/data/php${php_version}_md5.pl
    md5sum /www/server/php/${php_version}/sbin/php-fpm > /www/server/panel/data/php-fpm${php_version}_md5.pl
}
System_Lib(){
	if [ "${PM}" == "yum" ] || [ "${PM}" == "dnf" ] ; then
		Centos8Check=$(cat /etc/redhat-release|grep ' 8.'|grep -i centos)
		CentosStream8Check=$(cat /etc/redhat-release |grep -i "Centos Stream"|grep 8)
		Opencloud8Check=$(cat /etc/redhat-release |grep -i 'OpenCloudOS'|grep '8.6')
		if [ "${Centos8Check}" ] || [ "${CentosStream8Check}" ] || [ "${Opencloud8Check}" ]; then
			yum config-manager --set-enabled PowerTools
			yum config-manager --set-enabled powertools
		fi
		Pack="gcc gcc-c++ libsodium-devel sqlite-devel oniguruma-devel libwebp-devel libvpx-devel openssl-devel"
	elif [ "${PM}" == "apt-get" ]; then
		Pack="gcc g++ libsodium-dev libonig-dev libsqlite3-dev libcurl4-openssl-dev libwebp-dev libvpx-dev libc-ares-dev"
	fi
	${PM} install ${Pack} -y

	if [ "${OS_NAME}" == "opencloudos" ] && [ "${OS_V}" == "9" ];then
		yum install libicu-73.2-4.oc9.x86_64 -y 
	fi
}
Service_Add(){
	wget -O /etc/init.d/php-fpm-${php_version} ${download_Url}/init/php/php-fpm-${php_version}
	sed -i "s/# Provides:          php-fpm/# Provides:          php-fpm-"${php_version}"/g" /etc/init.d/php-fpm-${php_version}
	chmod +x /etc/init.d/php-fpm-${php_version}
	if [ "${PM}" == "yum" ] || [ "${PM}" == "dnf" ]; then
		chkconfig --add php-fpm-${php_version}
		chkconfig --level 2345 php-fpm-${php_version} on

	elif [ "${PM}" == "apt-get" ]; then
		update-rc.d php-fpm-${php_version} defaults
	fi

	if [ "$?" == "127" ];then
		wget -O /usr/lib/systemd/system/php-fpm-${php_version}.service ${download_Url}/init/systemd/php-fpm-${php_version}.service
		systemctl enable php-fpm-${php_version}.service
	fi

	/etc/init.d/php-fpm-${php_version} start 
}
Service_Del(){
	if [ "${PM}" == "yum" ] || [ "${PM}" == "dnf" ]; then
		chkconfig --del php-fpm-${php_version}
		chkconfig --level 2345 php-fpm-${php_version} off
	elif [ "${PM}" == "apt-get" ]; then
		update-rc.d php-fpm-${php_version} remove
	fi
	if [ -f "/usr/lib/systemd/system/php-fpm-${php_version}.service" ];then
		systemctl disable php-fpm-${php_version}.service
	fi
	rm -f /etc/init.d/php-fpm-$php_version
}
Install_Openssl_1_0_2(){
	if [ ! -f "/usr/local/openssl/bin/openssl" ];then
		cd ${run_path}
		wget ${download_Url}/src/openssl-${opensslVersion}.tar.gz
		tar -zxf openssl-${opensslVersion}.tar.gz
		cd openssl-${opensslVersion}
		./config --openssldir=/usr/local/openssl zlib-dynamic shared
		make -j${cpuCore} 
		make install
		echo  "/usr/local/openssl/lib" > /etc/ld.so.conf.d/zopenssl.conf
		ldconfig
		cd ..
		rm -f openssl-${opensslVersion}.tar.gz
		rm -rf openssl-${opensslVersion}
	fi
}
Install_Openssl_1_1_1(){
	openssl111Check=$(openssl version |grep 1.1.1)
	if [ ! -f "/usr/local/openssl111/bin/openssl" ] && [ -z "${openssl111Check}" ] || [ ! -f "/usr/local/openssl111/t.pl" ];then
	    rm -rf /usr/local/openssl111
		cd /usr/local
		if [ "${aarch64Check}" != "" ]; then
			wget -O ${OS_NAME}-${OS_V}-openssl111.tar.gz ${download_Url}/soft/lib/openssl/arm/${OS_NAME}-${OS_V}-openssl111.tar.gz -T 20
		else
			wget -O ${OS_NAME}-${OS_V}-openssl111.tar.gz ${download_Url}/soft/lib/openssl/${OS_NAME}-${OS_V}-openssl111.tar.gz -T 20	
		fi
		tar -zxf ${OS_NAME}-${OS_V}-openssl111.tar.gz
		rm -f ${OS_NAME}-${OS_V}-openssl111.tar.gz
		echo "/usr/local/openssl111/lib" >> /etc/ld.so.conf.d/zopenssl111.conf
		touch /usr/local/openssl111/t.pl
		ldconfig
		cd ${run_path}
	fi
}
Install_Curl(){
	if [ "${PM}" == "yum" ];then
		CURL_OPENSSL_LIB_VERSION=$(/usr/local/curl/bin/curl -V|grep -oE OpenSSL.*[0-9][a-z]|cut -f 2 -d "/")
		OPENSSL_LIB_VERSION=$(/usr/local/openssl/bin/openssl version|awk '{print $2}')
	fi
	if [ ! -f "/usr/local/curl/bin/curl" ] || [ "${CURL_OPENSSL_LIB_VERSION}" != "${OPENSSL_LIB_VERSION}" ];then
		wget ${download_Url}/src/curl-${curlVersion}.tar.gz
		tar -zxf curl-${curlVersion}.tar.gz
		cd curl-${curlVersion}
		rm -rf /usr/local/curl	
		./configure --prefix=/usr/local/curl --enable-ares --without-nss --with-ssl=/usr/local/openssl
		make -j${cpuCore}
		make install
		cd ..
		rm -f curl-${curlVersion}.tar.gz
		rm -rf curl-${curlVersion}
	fi
}
Install_Curl_New(){
	if [ ! -f "/usr/local/curl_2/bin/curl" ];then
		cd /usr/local
		if [ "${aarch64Check}" != "" ]; then
			wget -O ${OS_NAME}-${OS_V}-curl_2.tar.gz ${download_Url}/soft/lib/curl_2/arm/${OS_NAME}-${OS_V}-curl_2.tar.gz -T 20
		else
			wget -O ${OS_NAME}-${OS_V}-curl_2.tar.gz ${download_Url}/soft/lib/curl_2/${OS_NAME}-${OS_V}-curl_2.tar.gz -T 20	
		fi
		tar -zxf ${OS_NAME}-${OS_V}-curl_2.tar.gz
		rm -f ${OS_NAME}-${OS_V}-curl_2.tar.gz	
		cd ${run_path}
	fi
}
Install_Curl2(){
	LibCurlVer=$(/usr/local/curl/bin/curl -V|grep curl|awk '{print $2}'|cut -d. -f2)
	if [[ "${LibCurlVer}" -le "60" ]]; then
		if [ ! -f "/usr/local/curl2/bin/curl" ];then
			curlVer="7.64.1"
			wget ${download_Url}/src/curl-${curlVer}.tar.gz
			tar -xvf curl-${curlVer}.tar.gz
			cd curl-${curlVer}
			./configure --prefix=/usr/local/curl2 --enable-ares --without-nss --with-ssl=/usr/local/openssl
			make -j${cpuCore}
			make install
			cd ..
			rm -rf curl*
		fi
	fi
}
Install_Icu4c(){
	cd ${run_path}
	icu4cVer=$(/usr/bin/icu-config --version)
	if [ ! -f "/usr/bin/icu-config" ] || [ "${icu4cVer:0:2}" -gt "60" ];then
		cd /usr/local
		if [ "${aarch64Check}" != "" ]; then
			wget -O ${OS_NAME}-${OS_V}-icu.tar.gz ${download_Url}/soft/lib/icu/arm/${OS_NAME}-${OS_V}-icu.tar.gz -T 20
		else
			wget -O ${OS_NAME}-${OS_V}-icu.tar.gz ${download_Url}/soft/lib/icu/${OS_NAME}-${OS_V}-icu.tar.gz -T 20
		fi
		tar -zxf ${OS_NAME}-${OS_V}-icu.tar.gz
		rm -f ${OS_NAME}-${OS_V}-icu.tar.gz

		[ -f "/usr/bin/icu-config" ] && mv /usr/bin/icu-config /usr/bin/icu-config.bak 
		ln -sf /usr/local/icu/bin/icu-config /usr/bin/icu-config
		echo "/usr/local/icu/lib" > /etc/ld.so.conf.d/zicu.conf
		ldconfig
		cd ${run_path}
	fi
}
Install_Libzip(){
	if [ "${PM}" == "yum" ];then
		el=$(cat /etc/redhat-release|grep -iE 'CentOS|Red Hat'|grep -Eo '([0-9]+\.)+[0-9]+'|grep -Eo '^[0-9]')
		if [ "${el}" == "7" ];then
		    yum install cmake3 -y
			rpm -q libzip5-devel > /dev/null
			if [ "$?" -ne "0" ];then
				mkdir libzip
				cd libzip
				wget -O libzip5-1.5.2.rpm ${download_Url}/rpm/remi/${el}/libzip5-1.5.2.rpm
				wget -O libzip5-devel-1.5.2.rpm ${download_Url}/rpm/remi/${el}/libzip5-devel-1.5.2.rpm
				wget -O libzip5-tools-1.5.2.rpm ${download_Url}/rpm/remi/${el}/libzip5-tools-1.5.2.rpm
				yum install * -y
				cd ..
				rm -rf libzip
			fi
		else
			libzipVerCheck=$(yum list libzip|grep libzip|awk 'NR==1 {printf("%d",$2)}')
			if [ "${libzipVerCheck}" -ge "1" ];then
				yum install -y libzip-devel
			fi
		fi
	elif [ "${PM}" == "apt-get" ];then
		apt-get install libzip-dev -y
	fi
	
	LIBZIP_CHECK=$(pkg-config --list-all|grep libzip)
	if [ -z "${LIBZIP_CHECK}" ] ;then
		wget -O libzip-1.10.1.tar.gz ${download_Url}/src/libzip-1.10.1.tar.gz
		tar -xvf libzip-1.10.1.tar.gz
		cd libzip-1.10.1
		if [ "/usr/bin/cmake3" ];then
			cmake3 -DCMAKE_INSTALL_PREFIX=/usr/local/libzip
		else
			cmake -DCMAKE_INSTALL_PREFIX=/usr/local/libzip
		fi
		make
		make install
		cd ..
		rm -rf libzip-1.10.1
		rm -f libzip-1.10.1.tar.gz
	fi
	
	autoconfVer=$(autoconf -V|grep 'GNU Autoconf'|awk '{print $4}'|grep -oE .[0-9]+|grep -oE [0-9]+)
	if [ "${autoconfVer}" -lt "69" ]; then
		wget ${download_Url}/src/autoconf-2.69.tar.gz
		tar -xvf autoconf-2.69.tar.gz
		cd autoconf-2.69
		./configure --prefix=/usr
		make && make install
		cd ..
		rm -rf autoconf*
	fi

}
Install_Onig(){
	onigCheck=$(pkg-config --list-all|grep onig)
	if [ -z "${onigCheck}" ];then
		cd ${run_path}
		onigVer="6.9.6"
		wget -O onig-${onigVer}.tar.gz ${download_Url}/src/onig-${onigVer}.tar.gz
		tar  -xvf onig-${onigVer}.tar.gz
		cd onig-${onigVer}
		./configure --prefix=/usr/local/onig
		make -j${cpuCore}
		make install
		cd ..
		rm -rf onig-${onigVer}*
	fi
}
Install_Libsodium(){
	sodiumCheck=$(pkg-config --list-all|grep libsodium)
	if [ ! -f "/usr/local/libsodium/lib/libsodium.so" ];then
		cd /usr/local
		if [ "${aarch64Check}" != "" ]; then
			wget -O ${OS_NAME}-${OS_V}-libsodium.tar.gz ${download_Url}/soft/lib/libsodium/arm/${OS_NAME}-${OS_V}-libsodium.tar.gz -T 20
		else
			wget -O ${OS_NAME}-${OS_V}-libsodium.tar.gz ${download_Url}/soft/lib/libsodium/${OS_NAME}-${OS_V}-libsodium.tar.gz -T 20
		fi
		tar -zxf ${OS_NAME}-${OS_V}-libsodium.tar.gz
		rm -f ${OS_NAME}-${OS_V}-libsodium.tar.gz
		cd ${run_path}
	fi
	if [ "${php_version}" == "73" ];then
		if [ "${PM}" == "apt-get" ]; then
			GET_LIBSODIUM_VER=$(dpkg -l |grep libsodium-dev|awk '{print $3}'|cut -d '.' -f3|cut -d '-' -f1)
			if [ "${GET_LIBSODIUM_VER}" -lt "15" ];then
				apt-get remove -y libsodium-dev
			fi
		fi
	fi
}
Create_Fpm(){
	PHP_PM_TYPE="dynamic"
	MemTotal=`free -m | grep Mem | awk '{print  $2}'`
	if [ "${MemTotal}" ];then
		if [ "${MemTotal}" -le 2200 ];then
			PHP_PM_TYPE="ondemand"
		fi
	fi
	cat >${php_setup_path}/etc/php-fpm.conf<<EOF
[global]
pid = ${php_setup_path}/var/run/php-fpm.pid
error_log = ${php_setup_path}/var/log/php-fpm.log
log_level = notice

[www]
listen = /tmp/php-cgi-${php_version}.sock
listen.backlog = -1
listen.allowed_clients = 127.0.0.1
listen.owner = www
listen.group = www
listen.mode = 0600
user = www
group = www
pm = ${PHP_PM_TYPE}
pm.status_path = /phpfpm_${php_version}_status
pm.max_children = 30
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 10
request_terminate_timeout = 100
request_slowlog_timeout = 30
slowlog = var/log/slow.log
EOF
}
Set_PHP_FPM_Opt(){
	MemTotal=`free -m | grep Mem | awk '{print  $2}'`
	if [[ ${MemTotal} -gt 1024 && ${MemTotal} -le 2048 ]]; then
		sed -i "s#pm.max_children.*#pm.max_children = 30#" ${php_setup_path}/etc/php-fpm.conf
		sed -i "s#pm.start_servers.*#pm.start_servers = 5#" ${php_setup_path}/etc/php-fpm.conf
		sed -i "s#pm.min_spare_servers.*#pm.min_spare_servers = 5#" ${php_setup_path}/etc/php-fpm.conf
		sed -i "s#pm.max_spare_servers.*#pm.max_spare_servers = 10#" ${php_setup_path}/etc/php-fpm.conf
	elif [[ ${MemTotal} -gt 2048 && ${MemTotal} -le 4096 ]]; then
		sed -i "s#pm.max_children.*#pm.max_children = 50#" ${php_setup_path}/etc/php-fpm.conf
		sed -i "s#pm.start_servers.*#pm.start_servers = 5#" ${php_setup_path}/etc/php-fpm.conf
		sed -i "s#pm.min_spare_servers.*#pm.min_spare_servers = 5#" ${php_setup_path}/etc/php-fpm.conf
		sed -i "s#pm.max_spare_servers.*#pm.max_spare_servers = 20#" ${php_setup_path}/etc/php-fpm.conf
	elif [[ ${MemTotal} -gt 4096 && ${MemTotal} -le 8192 ]]; then
		sed -i "s#pm.max_children.*#pm.max_children = 100#" ${php_setup_path}/etc/php-fpm.conf
		sed -i "s#pm.start_servers.*#pm.start_servers = 10#" ${php_setup_path}/etc/php-fpm.conf
		sed -i "s#pm.min_spare_servers.*#pm.min_spare_servers = 10#" ${php_setup_path}/etc/php-fpm.conf
		sed -i "s#pm.max_spare_servers.*#pm.max_spare_servers = 30#" ${php_setup_path}/etc/php-fpm.conf
	elif [[ ${MemTotal} -gt 8192 && ${MemTotal} -le 16384 ]]; then
		sed -i "s#pm.max_children.*#pm.max_children = 150#" ${php_setup_path}/etc/php-fpm.conf
		sed -i "s#pm.start_servers.*#pm.start_servers = 15#" ${php_setup_path}/etc/php-fpm.conf
		sed -i "s#pm.min_spare_servers.*#pm.min_spare_servers = 15#" ${php_setup_path}/etc/php-fpm.conf
		sed -i "s#pm.max_spare_servers.*#pm.max_spare_servers = 30#" ${php_setup_path}/etc/php-fpm.conf
	elif [[ ${MemTotal} -gt 16384 ]]; then
		sed -i "s#pm.max_children.*#pm.max_children = 300#" ${php_setup_path}/etc/php-fpm.conf
		sed -i "s#pm.start_servers.*#pm.start_servers = 20#" ${php_setup_path}/etc/php-fpm.conf
		sed -i "s#pm.min_spare_servers.*#pm.min_spare_servers = 20#" ${php_setup_path}/etc/php-fpm.conf
		sed -i "s#pm.max_spare_servers.*#pm.max_spare_servers = 50#" ${php_setup_path}/etc/php-fpm.conf
	fi
	#backLogValue=$(cat ${php_setup_path}/etc/php-fpm.conf |grep max_children|awk '{print $3*1.5}')
	#sed -i "s#listen.backlog.*#listen.backlog = "${backLogValue}"#" ${php_setup_path}/etc/php-fpm.conf	
	sed -i "s#listen.backlog.*#listen.backlog = 8192#" ${php_setup_path}/etc/php-fpm.conf
}
Set_Phpini(){

	sed -i 's/post_max_size =.*/post_max_size = 50M/g' ${php_setup_path}/etc/php.ini
	sed -i 's/upload_max_filesize =.*/upload_max_filesize = 50M/g' ${php_setup_path}/etc/php.ini
	sed -i 's/;date.timezone =.*/date.timezone = PRC/g' ${php_setup_path}/etc/php.ini
	sed -i 's/short_open_tag =.*/short_open_tag = On/g' ${php_setup_path}/etc/php.ini
	sed -i 's/;cgi.fix_pathinfo=.*/cgi.fix_pathinfo=1/g' ${php_setup_path}/etc/php.ini
	sed -i 's/max_execution_time =.*/max_execution_time = 300/g' ${php_setup_path}/etc/php.ini
	sed -i 's/;sendmail_path =.*/sendmail_path = \/usr\/sbin\/sendmail -t -i/g' ${php_setup_path}/etc/php.ini
	sed -i 's/disable_functions =.*/disable_functions = passthru,exec,system,putenv,chroot,chgrp,chown,shell_exec,popen,proc_open,pcntl_exec,ini_alter,ini_restore,dl,openlog,syslog,readlink,symlink,popepassthru,pcntl_alarm,pcntl_fork,pcntl_waitpid,pcntl_wait,pcntl_wifexited,pcntl_wifstopped,pcntl_wifsignaled,pcntl_wifcontinued,pcntl_wexitstatus,pcntl_wtermsig,pcntl_wstopsig,pcntl_signal,pcntl_signal_dispatch,pcntl_get_last_error,pcntl_strerror,pcntl_sigprocmask,pcntl_sigwaitinfo,pcntl_sigtimedwait,pcntl_exec,pcntl_getpriority,pcntl_setpriority,imap_open,apache_setenv/g' ${php_setup_path}/etc/php.ini
	sed -i 's/display_errors = Off/display_errors = On/g' ${php_setup_path}/etc/php.ini
	sed -i 's/error_reporting =.*/error_reporting = E_ALL \& \~E_NOTICE/g' ${php_setup_path}/etc/php.ini

	if [ "${php_version}" = "52" ]; then
		sed -i "s#extension_dir = \"./\"#extension_dir = \"${php_setup_path}/lib/php/extensions/no-debug-non-zts-20060613/\"\n#" ${php_setup_path}/etc/php.ini
		sed -i 's#output_buffering =.*#output_buffering = On#' ${php_setup_path}/etc/php.ini
		sed -i 's/; cgi.force_redirect = 1/cgi.force_redirect = 0;/g' ${php_setup_path}/etc/php.ini
		sed -i 's/; cgi.redirect_status_env = ;/cgi.redirect_status_env = "yes";/g' ${php_setup_path}/etc/php.ini
	fi

	if [ "${php_version}" -ge "56" ]; then
		if [ -f "/etc/pki/tls/certs/ca-bundle.crt" ];then
			crtPath="/etc/pki/tls/certs/ca-bundle.crt"
		elif [ -f "/etc/ssl/certs/ca-certificates.crt" ]; then
			crtPath="/etc/ssl/certs/ca-certificates.crt"
		fi
		sed -i "s#;openssl.cafile=#openssl.cafile=${crtPath}#" ${php_setup_path}/etc/php.ini
		sed -i "s#;curl.cainfo =#curl.cainfo = ${crtPath}#" ${php_setup_path}/etc/php.ini
	fi

	sed -i 's/expose_php = On/expose_php = Off/g' ${php_setup_path}/etc/php.ini
	
}
Ln_PHP_Bin(){
	rm -f /usr/bin/php*
	rm -f /usr/bin/pear
	rm -f /usr/bin/pecl

    ln -sf ${php_setup_path}/bin/php /usr/bin/php
    ln -sf ${php_setup_path}/bin/phpize /usr/bin/phpize
    ln -sf ${php_setup_path}/bin/pear /usr/bin/pear
    ln -sf ${php_setup_path}/bin/pecl /usr/bin/pecl
    ln -sf ${php_setup_path}/sbin/php-fpm /usr/bin/php-fpm
}
Pear_Pecl_Set(){
 	if [ "${php_version}" -le "73" ];then
		pear config-set php_ini ${php_setup_path}/etc/php.ini
		pecl config-set php_ini ${php_setup_path}/etc/php.ini
	fi
}
Install_Composer(){
	if [ ! -f "/usr/bin/composer" ];then
		wget -O /usr/bin/composer ${download_Url}/install/src/composer.phar -T 20;
		chmod +x /usr/bin/composer
		if [ "${download_Url}" == "http://$CN:5880" ];then
			composer config -g repo.packagist composer https://packagist.phpcomposer.com
		fi
	fi
}
Download_Src(){
	php_setup_path="/www/server/php/${php_version}"
	mkdir -p ${php_setup_path}
	if [ "${actionType}" == "install" ];then
		/etc/init.d/php-fpm-$php_version stop
		rm -rf ${php_setup_path}/*
	fi
}
Install_Configure(){
	aarch64Check=$(uname -a|grep aarch64)
	if [ "${aarch64Check}" ];then
		CONFIGURE_BUILD_TYPE="--build=arm-linux"
		if [ "${php_version}"  == "55" ];then 
			wget -O /www/server/php/55/src/Zend/zend_multiply.h ${download_Url}/patch/php/php_55_zend_multiply.h
		elif [ "${php_version}"  == "56" ];then
			wget -O /www/server/php/56/src/Zend/zend_multiply.h ${download_Url}/patch/php/php_56_zend_multiply.h
		fi
	fi
	
	if [ "${php_version}" == "71" ] || [ "${php_version}" == "72" ] || [ "${php_version}" == "73" ];then
		export CXX="g++ -DTRUE=1 -DFALSE=0"
		export CC="gcc -DTRUE=1 -DFALSE=0"
		DEBIAN_12_C=$(cat /etc/issue|grep Debian|grep 12)
		if [ "${DEBIAN_12_C}" ];then
		    wget -O /www/server/php/${php_version}/src/ext/intl/breakiterator/codepointiterator_internal.cpp https://download.bt.cn//patch/php/debian-12-php-71-codepointiterator_internal.cpp
            wget -O /www/server/php/${php_version}/src/ext/intl/breakiterator/codepointiterator_internal.h https://download.bt.cn//patch/php/debian-12-php-71-codepointiterator_internal.h
		fi
	fi 

	if [ "${php_version}" -ge "73" ];then
		Install_Libzip
		Install_Onig
		Install_Libsodium
		Install_Curl2
		if [ -f "/usr/local/curl2/bin/curl" ]; then
			withCurl="/usr/local/curl2"
		else
			withCurl="/usr/local/curl"
		fi

		if [ -f "/usr/local/openssl111/bin/openssl" ];then
			 curlOpensslLIB=$(/usr/local/curl/bin/curl -V|grep -oE OpenSSL/1.1.1[a-Z]|cut -d '/' -f 2)
			 opensslVersion=$(/usr/local/openssl111/bin/openssl version|awk '{print $2}')
			 if [ "${curlOpensslLIB}" == "${opensslVersion}" ];then
			 	withOpenssl="/usr/local/openssl111"
			 else
			 	withOpenssl="/usr/local/openssl"
			 fi
		else
			withOpenssl="/usr/local/openssl"
		fi

		if [ "${php_version}" -ge "80" ];then
			opensslCheck=$(openssl version |grep 1.1.1)
			if [ -z "${opensslCheck}" ]; then
				if [ "${PM}" == "yum" ] || [ "${PM}" == "dnf" ] ; then
					yum install lksctp-tools-devel brotli-devel libssh2-devel -y
				elif [ "${PM}" == "apt-get" ]; then
					apt-get install libsctp-dev libbrotli-dev libssh2-1-dev -y
				fi
				Install_Openssl_1_1_1
				Install_Curl_New
				withOpenssl="/usr/local/openssl111"
				withCurl="/usr/local/curl_2"
			else
				withOpenssl=""
				withCurl=""
			fi
		fi
	fi
	
	if [ "${OS_NAME}" == "opencloudos" ] && [  "${OS_V}" == "9" ];then
        if [ -f "/lib64/libvpx.so.9" ]  && [ ! -f "/lib64/libvpx.so.8" ];then
            ln -sf /lib64/libvpx.so.9 /lib64/libvpx.so.8
            ldconfig
        fi
    fi
	
}
Install_PHP(){
	if [ "${actionType}" == "update" ]; then
		/etc/init.d/php-fpm-${php_version} stop
		sleep 2
		make install
		[ $? -ne 0 ] && Error_Msg
		sleep 1
		/etc/init.d/php-fpm-${php_version} start
		echo "${phpVersion}" > ${php_setup_path}/version.pl
		rm -f ${php_setup_path}/version_check.pl
		rm -f ${Setup_Path}/src.tar.gz 
		rm -rf ${php_setup_path}/src/Zend 
		MD5_check
		exit 0;
	fi
	
	cd ${Setup_Path}
	if [ "${aarch64Check}" != "" ]; then
		wget -O ${OS_NAME}-${OS_V}-php-${php_version}.tar.gz ${download_Url}/soft/php/arm/${php_version}/${OS_NAME}-${OS_V}-php-${php_version}.tar.gz -T 20
	else
		wget -O ${OS_NAME}-${OS_V}-php-${php_version}.tar.gz ${download_Url}/soft/php/${php_version}/${OS_NAME}-${OS_V}-php-${php_version}.tar.gz -T 20
	fi
	tar -zxf ${OS_NAME}-${OS_V}-php-${php_version}.tar.gz
	rm -f ${OS_NAME}-${OS_V}-php-${php_version}.tar.gz

	cd ${php_setup_path}

	echo "${phpVersion}" > ${php_setup_path}/version.pl

	if [ ! -f "${php_setup_path}/bin/php" ];then
		wget -O php.sh ${download_Url}/install/0/php.sh && sh php.sh install $version
		exit;
	fi

	${php_setup_path}/bin/php -v
	if [ "$?" != "0" ];then
		wget -O php.sh ${download_Url}/install/0/php.sh && sh php.sh install $version
		exit;
	fi	

	[ ! -f "${php_setup_path}/bin/php" ] && Error_Msg
	
	MD5_check
}
Install_Zip_ext(){
	zip_download_path="soft/lib/zip/${php_version}"
	if [ "${aarch64Check}" != "" ]; then
		zip_download_path="soft/lib/zip/arm/${php_version}"
	fi
	if [ "${php_version}" == "73" ];then
		wget -O /www/server/php/73/lib/php/extensions/no-debug-non-zts-20180731/zip.so ${download_Url}/${zip_download_path}/${OS_NAME}-${OS_V}-${php_version}-zip.so
	elif [ "${php_version}" == "74" ]; then
		wget -O /www/server/php/74/lib/php/extensions/no-debug-non-zts-20190902/zip.so ${download_Url}/${zip_download_path}/${OS_NAME}-${OS_V}-${php_version}-zip.so
	elif [ "${php_version}" == "80" ]; then
		wget -O /www/server/php/80/lib/php/extensions/no-debug-non-zts-20200930/zip.so ${download_Url}/${zip_download_path}/${OS_NAME}-${OS_V}-${php_version}-zip.so
	elif [ "${php_version}" == "81" ]; then
		wget -O /www/server/php/81/lib/php/extensions/no-debug-non-zts-20210902/zip.so ${download_Url}/${zip_download_path}/${OS_NAME}-${OS_V}-${php_version}-zip.so
	elif [ "${php_version}" == "82" ]; then
		wget -O /www/server/php/82/lib/php/extensions/no-debug-non-zts-20220829/zip.so ${download_Url}/${zip_download_path}/${OS_NAME}-${OS_V}-${php_version}-zip.so
	elif [ "${php_version}" == "83" ];then
		wget -O /www/server/php/83/lib/php/extensions/no-debug-non-zts-20230831/zip.so ${download_Url}/${zip_download_path}/${OS_NAME}-${OS_V}-${php_version}-zip.so
	elif [ "${php_version}" == "84" ];then
		wget -O /www/server/php/84/lib/php/extensions/no-debug-non-zts-20240924/zip.so ${download_Url}/${zip_download_path}/${OS_NAME}-${OS_V}-${php_version}-zip.so
	elif [ "${php_version}" == "85" ];then
		wget -O /www/server/php/85/lib/php/extensions/no-debug-non-zts-20250925/zip.so ${download_Url}/${zip_download_path}/${OS_NAME}-${OS_V}-${php_version}-zip.so
	fi

	grep -q '^extension = zip.so' ${php_setup_path}/etc/php.ini || echo "extension = zip.so" >> ${php_setup_path}/etc/php.ini

}
Install_Zend(){
	mkdir -p /usr/local/zend/php${php_version}
	if [ "${php_version}" -lt "70" ];then
		echo "Install ZendGuardLoader for PHP ${version}"
		echo "unavailable now."
		echo "Write ZendGuardLoader to php.ini..."
		wget -O php-ZendGuardLoader.tar.gz ${download_Url}/src/php-ZendGuardLoader.tar.gz
		tar -xvf php-ZendGuardLoader.tar.gz > /dev/null
		mv zend/ZendGuardLoader-${php_version}-${Is_64bit}.so /usr/local/zend/php${php_version}/ZendGuardLoader.so
		rm -f php-ZendGuardLoader.tar.gz
		rm -rf zend
			cat >>${php_setup_path}/etc/php.ini<<EOF
;eaccelerator

;ionCube

;opcache

[Zend ZendGuard Loader]
zend_extension=/usr/local/zend/php${php_version}/ZendGuardLoader.so
zend_loader.enable=1
zend_loader.disable_licensing=0
zend_loader.obfuscation_level_support=3
zend_loader.license_path=

;xcache
EOF
	else
		grep -q '^;ionCube' ${php_setup_path}/etc/php.ini || echo ";ionCube" >> ${php_setup_path}/etc/php.ini
		grep -q '^;opcache' ${php_setup_path}/etc/php.ini || echo ";opcache" >> ${php_setup_path}/etc/php.ini
	fi
}

Download_Conf(){
    for phpV in 52 53 54 55 56 70 71 72 73 74 80 81 82 83 84 85; do
    if [ ! -f "/www/server/nginx/enable-php-${phpV}.conf" ];then
        cat >/www/server/nginx/conf/enable-php-${phpV}.conf <<EOF
    location ~ [^/]\.php(/|$)
    {
        try_files \$uri =404;
        fastcgi_pass  unix:/tmp/php-cgi-${phpV}.sock;
        fastcgi_index index.php;
        include fastcgi.conf;
        include pathinfo.conf;
    }
EOF
    fi
    done
	if [ ! -f "/www/server/nginx/conf/enable-php-${php_version}.conf" ];then
		wget -O /www/server/nginx/conf/enable-php-${php_version}.conf ${download_Url}/conf/enable-php-${php_version}.conf
	fi
}

SetPHPMyAdmin(){
	if [ -f "/www/server/nginx/sbin/nginx" ]; then
		webserver="nginx"
	fi
	PHPVersion=""
	for phpV in 52 53 54 55 56 70 71 72 73 74 80 81 82 83 84 85
	do
		if [ -f "/www/server/php/${phpV}/bin/php" ]; then
			PHPVersion=${phpV}
		fi
	done

	[ -z "${PHPVersion}" ] && PHPVersion="00"
	if [ "${webserver}" == "nginx" ];then
		sed -i "s#$Root_Path/wwwroot/default#$Root_Path/server/phpmyadmin#" $Root_Path/server/nginx/conf/nginx.conf
		rm -f $Root_Path/server/nginx/conf/enable-php.conf
		\cp $Root_Path/server/nginx/conf/enable-php-$PHPVersion.conf $Root_Path/server/nginx/conf/enable-php.conf
		sed -i "/pathinfo/d" $Root_Path/server/nginx/conf/enable-php.conf
		/etc/init.d/nginx reload
	else
		sed -i "s#$Root_Path/wwwroot/default#$Root_Path/server/phpmyadmin#" $Root_Path/server/apache/conf/extra/httpd-vhosts.conf
		sed -i "0,/php-cgi/ s/php-cgi-\w*\.sock/php-cgi-${PHPVersion}.sock/" $Root_Path/server/apache/conf/extra/httpd-vhosts.conf
		/etc/init.d/httpd reload
	fi
}
Remove_Src(){
	cd ${php_setup_path}/src
	ls |grep -v ext|xargs rm -rf
	cd ext
	find -name tests|xargs rm -rf
}
Uninstall_PHP(){
	if [ -f "/www/server/php/${php_version}/rpm.pl" ];then
		yum remove -y bt-php${php_version}
		[ ! -f "/www/server/php/${php_version}/bin/php" ] && exit 0;
	fi

	if [ -f "/www/server/php/${php_version}/deb.pl" ];then
		apt-get remove -y bt-php${php_version}
	fi

	/etc/init.d/php-fpm-$php_version stop

	rm -rf $php_path/$php_version

	if [ -f "$Root_Path/server/phpmyadmin/version.pl" ];then
		SetPHPMyAdmin
	fi

	for phpV in 52 53 54 55 56 70 71 72 73 74 80 81 82 83 84 85;
	do
		if [ -f "/www/server/php/${phpV}/bin/php" ]; then
			rm -f /usr/bin/php
			ln -sf /www/server/php/${phpV}/bin/php /usr/bin/php
		fi
	done
}

actionType=$1
version=$2
php_version=${2/./}
php_52="5.2.17"
php_53="5.3.29"
php_54="5.4.45"
php_55='5.5.38'
php_56='5.6.40'
php_70='7.0.33'
php_71='7.1.33'
php_72='7.2.33'
php_73='7.3.32'
php_74='7.4.33'
php_80='8.0.26'
php_81='8.1.27'
php_82='8.2.34'
php_83='8.3.35'
php_84='8.4.26'
php_85='8.5.11'
opensslVersion="1.0.2u"
openssl111Version="1.1.1o"
nghttp2Version="1.42.0"
curlVersion="7.70.0"
if [ "$actionType" == 'install' ] || [ "$actionType" == 'update' ] ;then
	phpVersion=$(eval echo '$'{php_${php_version}})
	Get_Sys_Version
	System_Lib
	Install_Openssl_1_0_2
	Install_Curl
	Install_Icu4c
	Configure_Get
	Download_Src
	Install_Configure
	Install_PHP
	if [ "${php_version}" -ge "73" ];then
		Install_Zip_ext
	fi 
	Ln_PHP_Bin
	Create_Fpm
	Set_PHP_FPM_Opt
	Set_Phpini
	Download_Conf
	Install_Zend
	Pear_Pecl_Set
	Install_Composer
	Service_Add
	if [ -f "/www/server/nginx/sbin/nginx" ] || [ -f "/www/server/apache/bin/httpd" ];then 
		# echo "安装基础网站流量统计程序..."
		wget -O site_new_total.sh ${download_Url}/site_total/install.sh &> /dev/null 
		bash site_new_total.sh &> /dev/null
		rm -f site_new_total.sh
		# echo "安装基础网站流量统计程序完成"
	fi
elif [ "$actionType" == 'uninstall' ];then
	Uninstall_PHP
	Service_Del
fi