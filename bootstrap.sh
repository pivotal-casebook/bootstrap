#!/usr/bin/env bash

BOOTSTRAP_BASE="https://github.com/pivotal-casebook/bootstrap"
BOOTSTRAP_BIN="${BOOTSTRAP_BASE}/raw/master/bin/bootstrap.sh"
BOOTSTRAPRC="${HOME}/.brewstraprc"
RBENV_RUBY_VERSION="1.9.3-p125"
CHEF_DEPENDENCIES="zlib zlib-devel"
CHEF_SOLO_DEPENDENCIES="openssl openssl-devel"
PKG_INSTALLER="sudo yum -y"
GEM_INSTALL_FLAGS="--no-ri --no-rdoc"
clear

TOTAL=10
STEP=1
function print_step() {
  echo -e "\033[1m($(( STEP++ ))/${TOTAL}) ${1}\033[0m\n"
}

function print_warning() {
  echo -e "\033[1;33m${1}\033[0m\n"
}

function print_error() {
  echo -e "\033[1;31m${1}\033[0m\n"
  exit 1
}


echo -e "\033[1m\nStarting brewstrap...\033[0m\n"
echo -e "\n"
echo -e "Brewstrap will make sure your machine is bootstrapped and ready to run chef"
echo -e "by making sure curl, rbenv and chef are installed. From there it will"
echo -e "kick off a chef-solo run using whatever chef repository of cookbooks you point it at."
echo -e "\n"
echo -e "It expects the chef repo to exist as a public or private repository on github.com"
echo -e "You will need your github credentials so now might be a good time to login to your account."

[[ -s "$BOOTSTRAPRC" ]] && source "$BOOTSTRAPRC"

print_step "Installing required packages..."

print_step "Configuring sudo"
sudo /bin/bash -c "sudo sed -ibak 's/\senv_reset/!env_reset/' /etc/sudoers"

# [[ -z "$SKIP_YUM_UPDATE" ]] && $PKG_INSTALLER update
$PKG_INSTALLER install $CHEF_DEPENDENCIES
$PKG_INSTALLER install $CHEF_SOLO_DEPENDENCIES

print_step "Collecting information.."
if [ -z $GITHUB_LOGIN ]; then
  echo -n "Github Username: "
  stty echo
  read GITHUB_LOGIN
  echo ""
fi

if [ -z $GITHUB_PASSWORD ]; then
  echo -n "Github Password: "
  stty -echo
  read GITHUB_PASSWORD
  echo ""
fi

if [ -z $CHEF_REPO ]; then
  echo -n "Chef Repo (Take the github HTTP URL): "
  stty echo
  read CHEF_REPO
  echo ""
fi
stty echo

rm -f $BOOTSTRAPRC
echo "GITHUB_LOGIN=${GITHUB_LOGIN}" >> $BOOTSTRAPRC
echo "GITHUB_PASSWORD=${GITHUB_PASSWORD}" >> $BOOTSTRAPRC
echo "CHEF_REPO=${CHEF_REPO}" >> $BOOTSTRAPRC
chmod 0600 $BOOTSTRAPRC

GIT_PATH=`which git`
if [ $? != 0 ]; then
  print_step "$PKG_INSTALLER install git"
  $PKG_INSTALLER install git
  if [ ! $? -eq 0 ]; then
    print_error "Unable to install git!"
  fi
else
  print_step "Git already installed"
fi

CURL_PATH=`which curl`
if [ $? != 0 ]; then
  print_step "$PKG_INSTALLER install curl"
  $PKG_INSTALLER install curl
  if [ ! $? -eq 0 ]; then
    print_error "Unable to install curl!"
  fi
else
  print_step "curl already installed"
fi

if [ ! -d ~/.rbenv ]; then
  cd ~/ && git clone ${GIT_DEBUG} git://github.com/sstephenson/rbenv.git .rbenv
fi
unset GEM_PATH
unset GEM_HOME
unset MY_RUBY_HOME
(echo $PATH | grep "rbenv") || (test -e ~/.bash_profile  && cat ~/.bash_profile | grep PATH | grep rbenv) || false
if [ $? -eq 1 ]; then
  echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bash_profile
fi
grep "rbenv init" ~/.bash_profile
if [ $? -eq 1 ]; then
  echo "eval \"\$(rbenv init -)\"" >> ~/.bash_profile
fi
export PATH=$HOME/.rbenv/bin:$PATH
if [ ! -d ~/.rbenv/plugins/ruby-build ]; then
  mkdir -p ~/.rbenv/plugins && cd ~/.rbenv/plugins && git clone $GIT_DEBUG git://github.com/sstephenson/ruby-build.git
fi
gcc --version | head -n1 | grep llvm >/dev/null
if [ $? -eq 0 ]; then
  export CC="gcc-4.2"
fi
which rbenv
if [ $? -eq 1 ]; then
  print_error "Unable to find rbenv in ${PATH} !"
  exit 1
fi
rbenv versions | grep ${RBENV_RUBY_VERSION}
if [ ! $? -eq 0 ]; then
  rbenv install ${RBENV_RUBY_VERSION}
  rbenv rehash
  if [ ! $? -eq 0 ]; then
    print_error "Unable to install rbenv or ruby ${RBENV_RUBY_VERSION}!"
  fi
fi
USING_RBENV=1
RUBY_RUNNER=""
eval "$(rbenv init -)"
sudo chown -R $USER:$USER $HOME/.gem/
rbenv shell ${RBENV_RUBY_VERSION}
rbenv global ${RBENV_RUBY_VERSION}
gem specification --version '>=0.9.12' chef = 2>&1 | awk 'BEGIN { s = 0 } /^name:/ { s = 1; exit }; END { if(s == 0) exit 1 }'
if [ $? -gt 0 ]; then
  print_step "Installing chef gem"
  gem install chef $GEM_INSTALL_FLAGS
  rbenv rehash
  if [ ! $? -eq 0 ]; then
    print_error "Unable to install chef!"
  fi
else
  print_step "Chef already installed"
fi

if [ ! -d /tmp/chef ]; then
  CHEF_REPO=`echo ${CHEF_REPO} | sed -e "s|https://${GITHUB_LOGIN}@|https://${GITHUB_LOGIN}:${GITHUB_PASSWORD}@|"`
  CENSORED_REPO=`echo ${CHEF_REPO} | sed -e "s|${GITHUB_PASSWORD}|\*\*\*|"`
  print_step "Cloning chef repo (${CENSORED_REPO})"

  git clone ${CHEF_REPO} /tmp/chef
  if [ ! $? -eq 0 ]; then
    print_error "Unable to clone repo!"
  fi
  print_step "Updating submodules..."
  if [ -e /tmp/chef/.gitmodules ]; then
    sed -i -e "s/${GITHUB_LOGIN}@/${GITHUB_LOGIN}:${GITHUB_PASSWORD}@/g" /tmp/chef/.gitmodules
  fi
  cd /tmp/chef && git submodule update --init
  if [ ! $? -eq 0 ]; then
    print_error "Unable to update submodules!"
  fi
else
  print_step "Updating chef repo (password, if prompted, will be your github account password)"
  cd /tmp/chef && git pull && git submodule update --init
  if [ ! $? -eq 0 ]; then
    print_error "Unable to update repo! Bad password?"
  fi
fi

if [ ! -e /tmp/chef/node.json ]; then
  print_error "The chef repo provided has no node.json at the toplevel. This is required to know what to run."
fi

if [ ! -e /tmp/chef/solo.rb ]; then
  print_warning "No solo.rb found, writing one..."
  echo "file_cache_path '/tmp/chef-solo-brewstrap'" > /tmp/chef/solo.rb
  echo "cookbook_path '/tmp/chef/cookbooks'" > /tmp/chef/solo.rb
fi

print_step "Kicking off chef-solo (password will be your local user password)"

USER_HOME=$HOME

CHEF_COMMAND="GITHUB_PASSWORD=$GITHUB_PASSWORD GITHUB_LOGIN=$GITHUB_LOGIN chef-solo -j /tmp/chef/node.json -c /tmp/chef/solo.rb"
sudo env ${CHEF_COMMAND}
if [ ! $? -eq 0 ]; then
  print_error "BREWSTRAP FAILED!"
else
  print_step "BREWSTRAP FINISHED"
fi

if [ -n "$PS1" ]; then
  exec bash --login
fi
