stage { 'pre':
    before => Stage['main'],
}


node default {
    # needed for ruby2.4
    exec { 'apt-get install software-properties-common':
        provider => shell,
        command  => 'apt-get update && apt-get install -y software-properties-common'
    } ->
    exec { 'apt-add-repository':
        provider => shell,
        command  => 'apt-add-repository -y ppa:brightbox/ruby-ng && apt-get update'
    } ->
    exec { 'apt-get update':
        provider => shell,
        command  => 'apt-get update'
    }

    # general packages
    package { ['git', 'build-essential', 'vim']:
        ensure => installed,
    } ->
    # python packages
    package { ['python3', 'python3-dev', 'python3-pip', 'libxslt1-dev', 'zlib1g-dev', 'gettext', 'libpq-dev']:
        ensure => installed,
    }
    ->
    package { ['ruby2.4', 'ruby2.4-dev']:
        ensure => installed,
    } ->
    exec { "install sass":
        provider => shell,
        command => 'gem install sass'
    }


    class { 'postgresql::globals':
        python_package_name => 'python3'
    }

    class { 'postgresql::server':
    } -> postgresql::server::role { 'evap':
        password_hash  => postgresql_password('evap', 'evap'),
        createdb       => true
    } -> postgresql::server::db { 'evap':
        owner          => 'evap',
        user           => 'evap',
        password       => ''
    } -> package { 'libapache2-mod-wsgi-py3':
        ensure         => latest,
    } -> exec { '/vagrant/requirements.txt':
        user           => 'vagrant',
        provider       => shell,
        command        => 'pip3 --log-file /tmp/pip.log install --user -r /vagrant/requirements.txt'
    } -> exec { '/vagrant/requirements-dev.txt':
        user           => 'vagrant',
        provider       => shell,
        command        => 'pip3 --log-file /tmp/pip.log install --user -r /vagrant/requirements-dev.txt'
    } -> class { 'evap':
    }

    # apache environment
    class { 'apache':
        default_vhost => false,
        user          => 'vagrant',
        group         => 'vagrant',
    } ->
    exec {"fix apache's locale":
        provider => shell,
        # this comments in some line in some apache config file to fix the locale.
        # see https://github.com/fsr-itse/EvaP/issues/626
        # and https://docs.djangoproject.com/en/dev/howto/deployment/wsgi/modwsgi/#if-you-get-a-unicodeencodeerror
        command => "sed -i s,#.\\ /etc/default/locale,.\\ /etc/default/locale,g /etc/apache2/envvars"
    }
    class { 'apache::mod::wsgi':
        wsgi_python_path            => '/vagrant'
    } -> apache::vhost { 'evap':
        default_vhost               => true,
        vhost_name                  => '*',
        port                        => '80',
        docroot                     => '/vagrant/evap/static_collected',
        aliases                     => [ { alias => '/static', path => '/vagrant/evap/static_collected' } ],
        wsgi_daemon_process         => 'wsgi',
        wsgi_daemon_process_options => {
            processes => '2',
            threads => '15',
            display-name => '%{GROUP}',
            user => 'vagrant'
        },
        wsgi_process_group          => 'wsgi',
        wsgi_script_aliases         => { '/' => '/vagrant/evap/wsgi.py' }
    } -> class { 'apache::mod::expires':
        expires_by_type => [
            { 'text/css' => 'access plus 1 year' },
            { 'application/javascript' => 'access plus 1 year' },
        ]
    }

    exec { 'auto_cd_vagrant':
        provider    => shell,
        command     => 'echo "\ncd /vagrant" >> /home/vagrant/.bashrc'
    }

    exec { 'alias_python_python3':
        provider    => shell,
        # the sudo thing makes "sudo python foo" work
        command     => 'echo "\nalias python=python3\nalias sudo=\'sudo \'" >> /home/vagrant/.bashrc'
    }
}
