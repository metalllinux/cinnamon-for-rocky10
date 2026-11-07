%global build_type_safety_c 0

Summary:	A slick-looking LightDM greeter
Name:		slick-greeter
Version:	2.2.6
Release:	2.el10
License:	GPL-3.0-or-later
URL:		https://github.com/linuxmint/%{name}
Source0:	slick-greeter-2.2.6.tar.gz
Source1:	10_%{name}-cinnamon.gschema.override.in
Source2:	%{name}.conf

ExcludeArch:    %{ix86}

BuildRequires:	meson
BuildRequires:	desktop-file-utils
BuildRequires:	gettext-devel
BuildRequires:	pkgconfig(liblightdm-gobject-1)
BuildRequires:	pkgconfig(gtk+-3.0)
BuildRequires:	pkgconfig(libcanberra)
BuildRequires:  pkgconfig(xapp)
BuildRequires:	vala

Provides:	lightdm-greeter = 1.2
Provides:	lightdm-%{name} = %{version}

Requires:	lightdm%{?_isa}

# Themeing require
Requires:	google-noto-sans-fonts
Requires:	rocky-logos
Requires:	rocky-backgrounds


Obsoletes:  %{name}-mate < %{version}-%{release}

# Make sure cinnamon override is installed
Requires:	(%{name}-cinnamon = %{version}-%{release} if cinnamon)

%description
A cross-distro LightDM greeter based on unity-greeter.

%package -n %{name}-cinnamon
Summary: Slick-greeter customisation for the CINNAMON desktop
BuildArch: noarch
Requires: %{name} = %{version}-%{release}
# Themeing require
Requires:	rocky-backgrounds
Requires:	mint-y-icons
Requires:	mint-themes

%description -n %{name}-cinnamon
Slick-greeter customisation for the CINNAMON desktop.

%prep
%autosetup -p1

%{__install} -pm 0644 %{SOURCE2} %{name}.conf.example

%build
%meson
%meson_build


%install
%meson_install

%{__mkdir} -p %{buildroot}%{_datadir}/lightdm/lightdm.conf.d	\
	%{buildroot}%{_datadir}/glib-2.0/schemas	\
	%{buildroot}%{_sysconfdir}/lightdm

%{__install} --target-directory=%{buildroot}%{_datadir}/lightdm/lightdm.conf.d	\
	-Dpm 0644 debian/90-%{name}.conf

%{__sed} -e 's!@color@!#202020!g'	\
	-e 's!@wallpaper@!%{_datadir}/backgrounds/rocky-default-10-arizona-sunset.jpg!'	\
	< %{SOURCE1}								\
	> %{buildroot}%{_datadir}/glib-2.0/schemas/10_%{name}-cinnamon.gschema.override

%{__install} --target-directory=%{buildroot}%{_sysconfdir}/lightdm	\
	-Dpm 0644 %{SOURCE2}

%{__chmod} -c a+x %{buildroot}%{_bindir}/*

%find_lang %{name}


%check
%{_bindir}/desktop-file-validate %{buildroot}%{_datadir}/xgreeters/*.desktop


%pre
%{_sbindir}/update-alternatives --remove lightdm-greeter	\
	%{_datadir}/xgreeters/%{name}.desktop 2> /dev/null ||:


%files -f %{name}.lang
%doc debian/changelog README.md %{name}.conf.example
%license debian/copyright COPYING
%{_bindir}/%{name}-check-hidpi
%{_bindir}/%{name}-set-keyboard-layout
%{_bindir}/%{name}-enable-tap-to-click
%{_sbindir}/%{name}
%config(noreplace) %{_sysconfdir}/lightdm/%{name}.conf
%{_datadir}/%{name}/
%{_datadir}/xgreeters/
%{_datadir}/glib-2.0/schemas/x.dm.%{name}.gschema.xml
%{_datadir}/lightdm/lightdm.conf.d/90-%{name}.conf
%{_mandir}/man?/%{name}*

%files -n %{name}-cinnamon
%license COPYING
%{_datadir}/glib-2.0/schemas/10_%{name}-cinnamon.gschema.override

%changelog
* Sat Nov 07 2026 Team Chaotix <chaotix@metallinux.dev> - 2.2.6-2.el10
- Ship the tarball COPYING (GPL-3.0) as %%license in the
  slick-greeter-cinnamon subpackage; the main package already ships it.
  The conditional cinnamon subpackage pin now uses %{version}-%{release}
  (was hardcoded to 2.2.6-1.el10).
* Tue Nov 03 2026 Team Chaotix <chaotix@metallinux.dev> - 2.2.6-1.el10
- Rocky Linux 10 port of slick-greeter 2.2.6-4.fc45 (Fedora 45, koji build
  3064896, spec ref b9f38a9957b827924c204bcffcd0a850c4323f26). Distro
  substitutions: system-logos->rocky-logos, desktop-backgrounds-compat
  ->rocky-backgrounds, desktop-backgrounds-basic->rocky-backgrounds,
  mint-y-theme->mint-themes; dropped Recommends lightdm-settings and
  onboard (not packaged for Rocky); the wallpaper is the Rocky 10
  arizona-sunset background and the cinnamon subpackage version pin is
  fixed to 2.2.6-1.el10.
