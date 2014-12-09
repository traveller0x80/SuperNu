      module groupmod
      implicit none
c
c-- wavelength grid (gridmod has a copy as well)
      integer,target :: grp_ng=0
      real*8,allocatable :: grp_wl(:) !(gas_ng) wavelength grid
      real*8,allocatable :: grp_wlinv(:) !(gas_ng) wavelength grid
c
      save
c
      contains
c
c
      subroutine group_init(ng,wlarr)
c     -------------------------------
      implicit none
      integer,intent(in) :: ng
      real*8,intent(in) :: wlarr(ng+1)
c
      grp_ng = ng
      allocate(grp_wl(ng+1),grp_wlinv(ng+1))
      grp_wl = wlarr
      grp_wlinv = 1d0/wlarr
      end subroutine group_init
c
c
      elemental function specint0(tempinv,ig)
c     ---------------------------------------!{{{
      use physconstmod
      implicit none
      real*8 :: specint0
      real*8,intent(in) :: tempinv
      integer,intent(in) :: ig
************************************************************************
* Calculate x**3/(exp(x) - 1), where x = h*c/(wl*k*T)
************************************************************************
      real*8,parameter :: ftpi4=15d0/pc_pi**4
      real*8,parameter :: hck=pc_h*pc_c/pc_kb
      real*8 :: x,dx
c
      x = hck*tempinv
      dx = x*abs(grp_wlinv(ig+1) - grp_wlinv(ig))
      x = x*.5d0*(grp_wlinv(ig+1) + grp_wlinv(ig))
c
      specint0 = ftpi4 * dx * x**3/(exp(x) - 1d0)
c!}}}
      end function specint0
c
c
      pure function specintv(tempinv,mode) result(ss)
c     -----------------------------------------------!{{{
      use physconstmod
      implicit none
      real*8 :: ss(grp_ng)
      real*8,intent(in) :: tempinv
      integer,intent(in),optional :: mode
************************************************************************
* Integrate normalized Planck spectrum using Newton-Cotes formulae of
* different degrees.
************************************************************************
      real*8,parameter :: ftpi4=15d0/pc_pi**4
      real*8,parameter :: hck=pc_h*pc_c/pc_kb
      real*8,parameter :: one6th=ftpi4/6d0
      real*8,parameter :: one90th=ftpi4/90d0
      real*8,parameter :: onehalf=ftpi4/2d0
      real*8,parameter :: one=ftpi4
      real*8 :: xarr(grp_ng+1)
      real*8 :: farr(grp_ng+1)
      real*8 :: f2arr(grp_ng)
      integer :: imode
c
c-- default mode is linear
      imode = 1
      if(present(mode)) imode = mode
c
c-- x
      xarr = hck*tempinv*grp_wlinv
c
c-- edge values are always used
c
      select case(imode)
c-- constant
      case(0)
       ss = one*abs(xarr(2:)-xarr(:grp_ng)) *
     &   f(.5d0*(xarr(2:)+xarr(:grp_ng)))
c
c-- linear
      case(1)
       farr = f(xarr) !edge values
       ss = onehalf*abs(xarr(2:)-xarr(:grp_ng)) *
     &   (farr(2:)+farr(:grp_ng))
c
c-- quadratic
      case(2)
       farr = f(xarr) !edge values
       f2arr = f(.5d0*(xarr(2:) + xarr(:grp_ng))) !midpoints
c-- simpson's rule
       ss = one6th*abs(xarr(2:)-xarr(:grp_ng)) *
     &  (farr(2:) + farr(:grp_ng) + 4d0*f2arr)
c
c-- cubic
      case(4)
c-- quarter points
       f2arr = 12d0*f(.5d0*(xarr(2:) + xarr(:grp_ng))) + 32d0*(
     &   f(.25d0*xarr(2:) + .75d0*xarr(:grp_ng)) +
     &   f(.75d0*xarr(2:) + .25d0*xarr(:grp_ng)))
c-- Boole's rule
       ss = one90th*abs(xarr(2:)-xarr(:grp_ng)) *
     &   (7d0*(farr(2:) + farr(:grp_ng)) + f2arr)
c
c-- invalid
      case default
       ss = 0d0
      endselect
c
      contains
c
      elemental real*8 function f(x)
      real*8,intent(in) :: x
      f = x**3/(exp(x) - 1d0)
      end function
c!}}}
      end function specintv
c
c
      pure function specintvp(tempinv,i1,i2,mode) result(ss)
c     -----------------------------------------------!{{{
      use physconstmod
      implicit none
      real*8 :: ss(i2-i1+1)
      real*8,intent(in) :: tempinv
      integer,intent(in) :: i1,i2
      integer,intent(in),optional :: mode
************************************************************************
* Integrate normalized Planck spectrum using Newton-Cotes formulae of
* different degrees.
************************************************************************
      real*8,parameter :: ftpi4=15d0/pc_pi**4
      real*8,parameter :: hck=pc_h*pc_c/pc_kb
      real*8,parameter :: one6th=ftpi4/6d0
      real*8,parameter :: one90th=ftpi4/90d0
      real*8,parameter :: onehalf=ftpi4/2d0
      real*8,parameter :: one=ftpi4
      real*8 :: xarr(i2-i1+2)
      real*8 :: farr(i2-i1+2)
      real*8 :: f2arr(i2-i1+1)
      integer :: imode
c
c-- default mode is linear
      imode = 1
      if(present(mode)) imode = mode
c
c-- x
      xarr = hck*tempinv*grp_wlinv(i1:i2+1)
c
c-- edge values are always used
c
      select case(imode)
c-- constant
      case(0)
       ss = one*abs(xarr(2:)-xarr(:grp_ng)) *
     &   f(.5d0*(xarr(2:)+xarr(:grp_ng)))
c
c-- linear
      case(1)
       farr = f(xarr) !edge values
       ss = onehalf*abs(xarr(2:)-xarr(:grp_ng)) *
     &   (farr(2:)+farr(:grp_ng))
c
c-- quadratic
      case(2)
       farr = f(xarr) !edge values
       f2arr = f(.5d0*(xarr(2:) + xarr(:grp_ng))) !midpoints
c-- simpson's rule
       ss = one6th*abs(xarr(2:)-xarr(:grp_ng)) *
     &  (farr(2:) + farr(:grp_ng) + 4d0*f2arr)
c
c-- cubic
      case(4)
c-- quarter points
       f2arr = 12d0*f(.5d0*(xarr(2:) + xarr(:grp_ng))) + 32d0*(
     &   f(.25d0*xarr(2:) + .75d0*xarr(:grp_ng)) +
     &   f(.75d0*xarr(2:) + .25d0*xarr(:grp_ng)))
c-- Boole's rule
       ss = one90th*abs(xarr(2:)-xarr(:grp_ng)) *
     &   (7d0*(farr(2:) + farr(:grp_ng)) + f2arr)
c
c-- invalid
      case default
       ss = 0d0
      endselect
c
      contains
c
      elemental real*8 function f(x)
      real*8,intent(in) :: x
      f = x**3/(exp(x) - 1d0)
      end function
c!}}}
      end function specintvp
c
c
      end module groupmod
