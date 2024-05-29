%undefine __brp_mangle_shebangs

Name: redborder-cli
Version: %{__version}
Release: %{__release}%{?dist}
BuildArch: noarch
Summary: Package for redborder CLI

License: AGPL 3.0
URL: https://github.com/redBorder/redborder-manager
Source0: %{name}-%{version}.tar.gz

Requires: bash redborder-common redborder-rubyrvm bash-completion

%description
%{summary}

%prep
%setup -qn %{name}-%{version}

%build

%install
mkdir -p %{buildroot}/usr/lib/redborder/scripts
mkdir -p %{buildroot}/usr/lib/redborder/lib/rbcli
mkdir -p %{buildroot}/etc/bash_completion.d
cp resources/lib/* %{buildroot}/usr/lib/redborder/lib/rbcli
cp resources/scripts/* %{buildroot}/usr/lib/redborder/scripts
cp resources/rbcli_bash_completion %{buildroot}/etc/bash_completion.d/rbcli
chmod 0644 %{buildroot}/usr/lib/redborder/lib/rbcli/*
chmod 0755 %{buildroot}/usr/lib/redborder/scripts/*
chmod 0644 %{buildroot}/etc/bash_completion.d/*

%pre

%post
/usr/lib/redborder/bin/rb_rubywrapper.sh -c

%files
%defattr(0755,root,root)
/usr/lib/redborder/scripts
%defattr(0644,root,root)
/usr/lib/redborder/lib/rbcli/*
/etc/bash_completion.d/*

%doc

%changelog
* Thu May 23 2024 Miguel Negrón <manegron@redborder.com>
- Rename red to rbcli

* Wed Feb 01 2023 Luis Blanco <ljblanco@redborder.com> -
- unliked reference for the IPS and Proxy for the red command

* Tue Jan 21 2022 David Vanhoucke <dvanhoucke@redborder.com> - 0.0.8-1
- adding extra functionality

* Tue Jan 17 2017 Juan J. Prieto <jjprieto@redborder.com> - 0.0.1-1
- first spec version

