#!/bin/bash

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SOURCE="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

mkdir -p $SOURCE/versions
cd $SOURCE/versions

# current MarkLogic symlink
sym=$(readlink ~/Library/MarkLogic)

while getopts :fk: opt; do
  case $opt in
    f) forcing=true ;;
    k) keeping=$OPTARG ;;
  esac
done
shift $((OPTIND-1))

versiondir() {
  echo "$SOURCE/versions/$1"
}

hasversion() {
  vdir=$(versiondir $1)
  if [ ! -d $vdir ]; then
    return 1
  fi
  return 0
}

uninstall() {
  echo "Uninstalling conventional MarkLogic"
  rm -fr ~/Library/MarkLogic
  rm -fr ~/Library/Application\ Support/MarkLogic
  rm -fr ~/Library/StartupItems/MarkLogic 
  rm -fr ~/Library/PreferencePanes/MarkLogic.prefPane
}

capture() {
  echo "Keeping current installation as $1"
  mkdir -p $SOURCE/versions/$1/StartupItems
  cp -a ~/Library/MarkLogic $SOURCE/versions/$1/MarkLogic
  cp -a ~/Library/Application\ Support/MarkLogic $SOURCE/versions/$1/Support
  cp -a ~/Library/StartupItems/MarkLogic $SOURCE/versions/$1/StartupItems/MarkLogic
  cp -a ~/Library/PreferencePanes/MarkLogic.prefPane $SOURCE/versions/$1/MarkLogic.prefPane
  # make sure everything is owned by this user
  _user=$(who am i | awk '{print $1}')
  _group=$(id -g $_user)
  chown -R $_user:$_group $SOURCE/versions/$1
}

# returns the PID of the running MarkLogic process, if there is one
mlpid() {
  return 0
}

switchto() {
  echo "switching to $1"
  #TODO update symlinks and system settings
}

isactive() {
  if [ ! -z $sym ] && [ $(basename $sym) = $1 ]; then
    return 0
  fi
  return 1
}

case "$1" in 

  # syntax:  mlvm list
  list)
    echo "Installed MarkLogic Versions:"
    for file in *; do
      mark='-'
      if isactive $file ; then
        mark='*'
      fi
      test -d "$file" && echo "$mark $file"
    done
    ;;

  # syntax: mlvm use <version_name>
  use)
    if [ "$#" -ne 2 ]; then 
      echo "You must specify which version to use.  'mlvm list' to see available versions"
      exit 1
    fi
    #TODO ensure the specified version exists
    #TODO check for any running MarkLogic processes
    if [ mlpid ]; then 
      echo "Stopping server" 
    fi
    switchto $2
    ;;

  # syntax:  mlvm install <version_name> <dmg_file>
  install) #installs a new .dmg version of ML
    #TODO download automatically, for now it requires the path to a previously downloaded .dmg
    vdir=$SOURCE/versions/$2
    if [ -d $vdir ]; then
      echo "$2 is already installed"
      exit 1
    fi
    # mount the dmg
    mpoint=$(date +%s)$RANDOM
    mpoint=$SOURCE/.mounts/$mpoint
    echo "Mounting dmg"
    mkdir -p $mpoint
    hdiutil attach $3 -nobrowse -quiet -mountpoint $mpoint
    mkdir -p $vdir
    echo "Extracting contents"
    tar xfz $mpoint/*.pkg/Contents/Archive.pax.gz -C $vdir
    mkdir -p $vdir/Support/Data
    echo "cleaning up"
    hdiutil detach $mpoint -quiet
    rm -fr $mpoint
    ;;

  # syntax: mlvm remove <version_name>
  remove)
    if [ -z $2 ]; then
      echo "usage: mlvm remove <version_name>"
      echo "use 'mlvm list' to see a list of available versions"
      exit 1
    fi
    vdir=$SOURCE/versions/$2
    if [ ! -d $vdir ]; then
      echo "\"$2\" is not installed"
      exit 1
    fi
    if $(isactive $2) ; then
      echo "\"$2\" is the active version.  Use -f to force an uninstall or 'mlvm use <version_name>' to use a different version before removing \"$2\"."
      exit 1
    fi
    rm -fr $SOURCE/versions/$2
    echo "removed \"$2\""
    ;;

  stop)
    ~/Library/StartupItems/MarkLogic/MarkLogic stop
    ;;

  start)
    ~/Library/StartupItems/MarkLogic/MarkLogic start
    ;;

  status)
    if [ -z $sym]; then
      echo 'You are not currently using mlvm.'
      echo
      echo "Run 'mlvm install <version_name> <dmg_file>' to install a new version. (Note: this will remove an existing installation made without mlvm)"
      echo
      echo "If you have previously installed a version of MarkLogic, FIRST run 'mlvm -k <version_name> prepare' to retain it along with future mlvm installations. Otherwise it will be replaced and data will be lost."      
      exit 1
    fi
    echo "Active ML version: $(basename $sym)"
    ;;

  # syntax: mlvm [-k <version_name>] prepare
  prepare) # prepares for use of mlvm by uninstalling existing MarkLogic, can optionally back up your existing install as a version
    if [ -d ~/Library/MarkLogic ]; then
      echo "Detected an existing installation of MarkLogic"
      if [ -z $keeping ] && [ -z $forcing ] ; then
        echo "Any existing MarkLogic data will be lost in the process unless kept.  You must either: "
        echo "  'mlvm -k <version_name> prepare' to retain the current version with mlvm, or "
        echo "  'mlvm -f prepare' to force an uninstallation and loss of data"
        exit 1
      fi
      if [ "$(id -u)" != "0" ]; then
        echo "This command requires root privileges.  Please run as sudo";
        exit 1
      fi
      #uninstalls the current ML installation, should probably ask if user wants to capture or update before proceeding
      #TODO check if any running MarkLogic processes
      if [ ! -z $keeping ]; then
        if hasversion $keeping ; then
          echo "\"$keeping\" already exists"
          exit 1
        fi
        capture $keeping
      fi
      uninstall
    else
      echo "Did not detect an existing install of MarkLogic"
    fi
    # this allows us to still use the prefpane and change current version without sudo later
    mkdir -p $SOURCE/versions/.current
    _user=$(who am i | awk '{print $1}')
    _group=$(id -g $_user)
    chown -R $_user:$_group $SOURCE/versions/
    ln -s $SOURCE/versions/.current/ ~/Library/StartupItems/MarkLogic

    echo "Ready to manage MarkLogic versions with mlvm."
    echo "Use 'mlvm list' to see installed versions"
    echo "Use 'mlvm install <version_name> <dmg_file>' to install a version"
    echo "Use 'mlvm use <version_name>' to switch to an installed version"
    echo "Use 'mlvm remove <version_name>' to remove an installed version (not recoverable)"
    ;;

  *) 
    echo "usage: mlvm [list, use (version), prepare, capture (version)]"
    exit 1

esac 