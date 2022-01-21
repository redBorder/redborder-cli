Name: redborder-cli
Version: %{__version}
Release: %{__release}%{?dist}
BuildArch: noarch
Summary: Package for redborder CLI

License: AGPL 3.0
URL: https://github.com/redBorder/redborder-manager
Source0: %{name}-%{version}.tar.gz

Requires: bash redborder-common redborder-rubyrvm bash-completion bash-completion-extras

%description
%{summary}

%prep
%setup -qn %{name}-%{version}

%build

%install
mkdir -p %{buildroot}/usr/lib/redborder/scripts
mkdir -p %{buildroot}/usr/lib/redborder/lib/red
mkdir -p %{buildroot}/etc/bash_completion.d
cp resources/lib/* %{buildroot}/usr/lib/redborder/lib/red
cp resources/scripts/* %{buildroot}/usr/lib/redborder/scripts
cp resources/red_bash_completion %{buildroot}/etc/bash_completion.d/red
chmod 0644 %{buildroot}/usr/lib/redborder/lib/red/*
chmod 0755 %{buildroot}/usr/lib/redborder/scripts/*
chmod 0644 %{buildroot}/etc/bash_completion.d/*

%pre

%post
/usr/lib/redborder/bin/rb_rubywrapper.sh -c

%files
%defattr(0755,root,root)
/usr/lib/redborder/scripts
%defattr(0644,root,root)
/usr/lib/redborder/lib/red/*
/etc/bash_completion.d/*

%doc

%changelog
* Tue Jan 21 2022 David Vanhoucke <dvanhoucke@redborder.com> - 0.0.8-1
- adding extra functionality
* Tue Jan 17 2017 Juan J. Prieto <jjprieto@redborder.com> - 0.0.1-1
- first spec version

