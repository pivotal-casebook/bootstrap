#!/usr/bin/env bash

BOOTSTRAP_BASE="https://github.com/pivotal-casebook/bootstrap"
BOOTSTRAP_BIN="${BOOTSTRAP_BASE}/raw/master/bin/bootstrap.sh"
BOOTSTRAPRC="${HOME}/.brewstraprc"
RVM_URL="https://raw.github.com/wayneeseguin/rvm/master/binscripts/rvm-installer"
RVM_MIN_VERSION="185"
RVM_RUBY_VERSION="ruby-1.9.3-p0"
CHEF_DEPENDENCIES="zlib1g zlib1g-dev"
RVM_DEPENDENCIES="bzip2"
CHEF_SOLO_DEPENDENCIES="openssl libssl-dev"
PKG_INSTALLER="sudo apt-get -y"
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
echo -e "by making sure curl, RVM and chef are installed. From there it will"
echo -e "kick off a chef-solo run using whatever chef repository of cookbooks you point it at."
echo -e "\n"
echo -e "It expects the chef repo to exist as a public or private repository on github.com"
echo -e "You will need your github credentials so now might be a good time to login to your account."

[[ -s "$BOOTSTRAPRC" ]] && source "$BOOTSTRAPRC"

print_step "Installing required packages..."
$PKG_INSTALLER install $RVM_DEPENDENCIES
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

if [ -z $GITHUB_TOKEN ]; then
  echo -n "Github Token: "
  stty echo
  read GITHUB_TOKEN
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
echo "GITHUB_TOKEN=${GITHUB_TOKEN}" >> $BOOTSTRAPRC
echo "CHEF_REPO=${CHEF_REPO}" >> $BOOTSTRAPRC
chmod 0600 $BOOTSTRAPRC

GIT_PATH=`which git`
if [ $? != 0 ]; then
  print_step "$PKG_INSTALLER install git-core"
  $PKG_INSTALLER install git-core
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

if [ ! -e ~/.rvm/bin/rvm ]; then
  print_step "Installing RVM"
  bash -s stable < <( curl -fsSL ${RVM_URL} )
  if [ ! $? -eq 0 ]; then
    print_error "Unable to install RVM!"
  fi
else
  RVM_VERSION=`~/.rvm/bin/rvm --version | cut -f 2 -d ' ' | head -n2 | tail -n1 | sed -e 's/\.//g'`
  if [ $RVM_VERSION -lt $RVM_MIN_VERSION ]; then
    print_step "RVM needs to be upgraded..."
    ~/.rvm/bin/rvm get 1.8.5
  else
    print_step "RVM already installed"
  fi
fi
DOT_PROFILE_RVM=`grep rvm ~/.profile`
if [ $? -eq 0 ]; then
    source ~/.profile
    RVM_ENV_VARS="~/.profile"
else
    source ~/.bash_profile
    RVM_ENV_VARS="~/.bash_profile"
fi

rvm list | grep ${RVM_RUBY_VERSION}
if [ $? -gt 0 ]; then
  print_step "Installing RVM Ruby ${RVM_RUBY_VERSION}"
  rvm install ${RVM_RUBY_VERSION}
  if [ ! $? -eq 0 ]; then
    print_error "Unable to install RVM ${RVM_RUBY_VERSION}"
  fi
else
  print_step "RVM Ruby ${RVM_RUBY_VERSION} already installed"
fi

rvm ${RVM_RUBY_VERSION} exec gem specification --version '>=0.9.12' chef 2>&1 | awk 'BEGIN { s = 0 } /^name:/ { s = 1; exit }; END { if(s == 0) exit 1 }'
if [ $? -gt 0 ]; then
  print_step "Installing chef gem"
  sh -c "rvm ${RVM_RUBY_VERSION} exec gem install chef"
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
  if [ -e /tmp/chef/.rvmrc ]; then
    rvm rvmrc trust /tmp/chef/
  fi
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
sudo -Es env GITHUB_PASSWORD=$GITHUB_PASSWORD GITHUB_LOGIN=$GITHUB_LOGIN GITHUB_TOKEN=$GITHUB_TOKEN HOME=$USER_HOME /bin/bash -lc "source ${RVM_ENV_VARS} && rvm ${RVM_RUBY_VERSION} exec chef-solo -l debug -j /tmp/chef/node.json -c /tmp/chef/solo.rb"

if [ ! $? -eq 0 ]; then
  print_error "BOOTSTRAP FAILED!"
else
  print_step "BOOTSTRAP FINISHED"
fi
exec bash --login
