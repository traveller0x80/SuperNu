! © 2023. Triad National Security, LLC. All rights reserved.
! This program was produced under U.S. Government contract 89233218CNA000001 for Los Alamos National
! Laboratory (LANL), which is operated by Triad National Security, LLC for the U.S. Department of
! Energy/National Nuclear Security Administration. All rights in the program are reserved by Triad
! National Security, LLC, and the U.S. Department of Energy/National Nuclear Security Administration.
! The Government is granted for itself and others acting on its behalf a nonexclusive, paid-up,
! irrevocable worldwide license in this material to reproduce, prepare. derivative works, distribute
! copies to the public, perform publicly and display publicly, and to permit others to do so.
!This file is part of SuperNu.  SuperNu is released under the terms of the GNU GPLv3, see COPYING.
!Copyright (c) 2013-2022 Ryan T. Wollaeger and Daniel R. van Rossum.  All rights reserved.
subroutine leakage_opacity3

  use miscmod
  use gridmod
  use groupmod
  use timestepmod
  use transportmod
  use physconstmod
  implicit none
!##################################################
  !This subroutine computes
  !DDMC 3D lumped leakage opacities.
!##################################################
  logical :: lhelp
  integer :: i,j,k, ig,igemitmax
  integer :: icnb(6) !neighbor cells
  real*8 :: thelp, dist, help, emitmax
  real*8 :: speclump, caplump, doplump, specval
  real*8 :: specarr(grp_ng)
  real*8 :: pp, alb, eps, beta
!-- statement functions
  integer :: l
  real*8 :: dx,dy,dz
  dx(l) = grd_xarr(l+1) - grd_xarr(l)
  dy(l) = grd_yarr(l+1) - grd_yarr(l)
  dz(l) = grd_zarr(l+1) - grd_zarr(l)
!
!-- setting vel-space helper
  if(grd_isvelocity) then
     thelp = tsp_t
  else
     thelp = 1d0
  endif

!
!-- calculating leakage opacities
  do k=1,grd_nz
  do j=1,grd_ny
  do i=1,grd_nx
     l = grd_icell(i,j,k)
!
!-- work distribution
     if(l<grd_idd1) cycle
     if(l>grd_idd1+grd_ndd-1) cycle
!
!-- zero
     grd_opaclump(:,l) = 0d0
!
!-- neighbors
     icnb(1) = grd_icell(max(i-1,1),j,k)      !left neighbor
     icnb(2) = grd_icell(min(i+1,grd_nx),j,k) !right neighbor
     icnb(3) = grd_icell(i,max(j-1,1),k)      !left neighbor
     icnb(4) = grd_icell(i,min(j+1,grd_ny),k) !right neighbor
     icnb(5) = grd_icell(i,j,max(k-1,1))      !left neighbor
     icnb(6) = grd_icell(i,j,min(k+1,grd_nz)) !right neighbor
!
!-- distance
     dist = min(dx(i),dy(j),dz(k))*thelp
!
!-- initializing Planck integral vectorized
     call specintv(grd_tempinv(l),grp_ng,specarr)
     speclump = sum(specarr, grd_cap(:,l)*dist>=trn_taulump .and. &
       (grd_sig(l) + grd_cap(:,l))*dist >= trn_tauddmc)
     if(speclump>0d0) then
        speclump = 1d0/speclump
     else
        speclump = 0d0
     endif
     grd_opaclump(7,l) = speclump
!
!-- caplump
     caplump = 0d0
     emitmax = 0d0
     igemitmax = 0
     do ig=1,grp_ng
        if(grd_cap(ig,l)*dist < trn_taulump) cycle
        if((grd_sig(l) + grd_cap(ig,l))*dist < trn_tauddmc) cycle
        help = specarr(ig)*grd_cap(ig,l)
        caplump = caplump + help
        if(help > emitmax) then
           emitmax = help
           igemitmax = ig
        endif
     enddo
!-- doplump
     doplump = 0d0
     if(grd_isvelocity) then
        do ig=1,grp_ng-1
           if(grd_cap(ig,l)*dist < trn_taulump) cycle
           if(grd_cap(ig+1,l)*dist >= trn_taulump) cycle
           if((grd_sig(l) + grd_cap(ig,l))*dist < trn_tauddmc) cycle
           help = dopspeccalc(grd_tempinv(l),ig) / (pc_c*tsp_t)
           doplump = doplump + help
        enddo
     endif
!-- store regrouped data
     grd_opaclump(8,l) = caplump
     grd_opaclump(9,l) = igemitmax
     grd_opaclump(10,l) = doplump
!
!-- lumping opacity
     do ig=1,grp_ng
        if(grd_cap(ig,l)*dist < trn_taulump) cycle
        if((grd_sig(l) + grd_cap(ig,l))*dist < trn_tauddmc) cycle
!
!-- obtaining spectral weight
        specval = specarr(ig)
!
!-- calculating i->i-1 leakage opacity
        if(i==1) then
           lhelp = .true.
        else
           lhelp = (grd_cap(ig,icnb(1))+ &
              grd_sig(icnb(1)))*min(dx(i-1),dy(j),dz(k)) * &
              thelp<trn_tauddmc
        endif
!
        if(lhelp) then
!-- DDMC interface
           pp = ddmc_emiss_bc(dx(i)*thelp, grd_fcoef(l), &
                grd_cap(ig,l), grd_sig(l), pc_dext)
           grd_opaclump(1,l) = grd_opaclump(1,l)+(specval*speclump)*&
                0.5d0*pp/(thelp*dx(i))
        else
!-- DDMC interior
           help = ((grd_sig(l)+grd_cap(ig,l))*dx(i)+&
                (grd_sig(icnb(1))+grd_cap(ig,icnb(1)))*dx(i-1))*thelp
           grd_opaclump(1,l) = grd_opaclump(1,l)+(specval*speclump)*&
                (2d0/3d0)/(help*dx(i)*thelp)
        endif

!
!-- calculating i->i+1 leakage opacity
        if(i==grd_nx) then
           lhelp = .true.
        else
           lhelp = (grd_cap(ig,icnb(2))+ &
              grd_sig(icnb(2)))*min(dx(i+1),dy(j),dz(k)) * &
              thelp<trn_tauddmc
        endif
!
        if(lhelp) then
!-- DDMC interface
           pp = ddmc_emiss_bc(dx(i)*thelp, grd_fcoef(l), &
                grd_cap(ig,l), grd_sig(l), pc_dext)
           grd_opaclump(2,l) = grd_opaclump(2,l)+(specval*speclump)*&
                0.5d0*pp/(thelp*dx(i))
        else
!-- DDMC interior
           help = ((grd_sig(l)+grd_cap(ig,l))*dx(i)+&
                (grd_sig(icnb(2))+grd_cap(ig,icnb(2)))*dx(i+1))*thelp
           grd_opaclump(2,l) = grd_opaclump(2,l)+(specval*speclump)*&
                (2d0/3d0)/(help*dx(i)*thelp)
        endif

!
!-- calculating j->j-1 leakage opacity
        if(j==1) then
           lhelp = .true.
        else
           lhelp = (grd_cap(ig,icnb(3))+ &
              grd_sig(icnb(3)))*min(dx(i),dy(j-1),dz(k)) * &
              thelp<trn_tauddmc
        endif
!
        if(lhelp) then
!-- DDMC interface
           pp = ddmc_emiss_bc(dy(j)*thelp, grd_fcoef(l), &
                grd_cap(ig,l), grd_sig(l), pc_dext)
           grd_opaclump(3,l) = grd_opaclump(3,l)+(specval*speclump)*&
                0.5d0*pp/(thelp*dy(j))
        else
!-- DDMC interior
           help = ((grd_sig(l)+grd_cap(ig,l))*dy(j)+&
                (grd_sig(icnb(3))+grd_cap(ig,icnb(3)))*dy(j-1))*thelp
           grd_opaclump(3,l) = grd_opaclump(3,l)+(specval*speclump)*&
                (2d0/3d0)/(help*dy(j)*thelp)
        endif

!
!-- calculating j->j+1 leakage opacity
        if(j==grd_ny) then
           lhelp = .true.
        else
           lhelp = (grd_cap(ig,icnb(4))+ &
              grd_sig(icnb(4)))*min(dx(i),dy(j+1),dz(k)) * &
              thelp<trn_tauddmc
        endif
!
        if(lhelp) then
!-- DDMC interface
           pp = ddmc_emiss_bc(dy(j)*thelp, grd_fcoef(l), &
                grd_cap(ig,l), grd_sig(l), pc_dext)
           grd_opaclump(4,l) = grd_opaclump(4,l)+(specval*speclump)*&
                0.5d0*pp/(thelp*dy(j))
        else
!-- DDMC interior
           help = ((grd_sig(l)+grd_cap(ig,l))*dy(j)+&
                (grd_sig(icnb(4))+grd_cap(ig,icnb(4)))*dy(j+1))*thelp
           grd_opaclump(4,l) = grd_opaclump(4,l)+(specval*speclump)*&
                (2d0/3d0)/(help*dy(j)*thelp)
        endif

!
!-- calculating k->k-1 leakage opacity
        if(k==1) then
           lhelp = .true.
        else
           lhelp = (grd_cap(ig,icnb(5))+ &
              grd_sig(icnb(5)))*min(dx(i),dy(j),dz(k-1)) * &
              thelp<trn_tauddmc
        endif
!
        if(lhelp) then
!-- DDMC interface
           pp = ddmc_emiss_bc(dz(k)*thelp, grd_fcoef(l), &
                grd_cap(ig,l), grd_sig(l), pc_dext)
           grd_opaclump(5,l) = grd_opaclump(5,l)+(specval*speclump)*&
                0.5d0*pp/(thelp*dz(k))
        else
!-- DDMC interior
           help = ((grd_sig(l)+grd_cap(ig,l))*dz(k)+&
                (grd_sig(icnb(5))+grd_cap(ig,icnb(5)))*dz(k-1))*thelp
           grd_opaclump(5,l) = grd_opaclump(5,l)+(specval*speclump)*&
                (2d0/3d0)/(help*dz(k)*thelp)
        endif

!
!-- calculating k->k+1 leakage opacity
        if(k==grd_nz) then
           lhelp = .true.
        else
           lhelp = (grd_cap(ig,icnb(6))+ &
              grd_sig(icnb(6)))*min(dx(i),dy(j),dz(k+1)) * &
              thelp<trn_tauddmc
        endif
!
        if(lhelp) then
!-- DDMC interface
           pp = ddmc_emiss_bc(dz(k)*thelp, grd_fcoef(l), &
                grd_cap(ig,l), grd_sig(l), pc_dext)
           grd_opaclump(6,l) = grd_opaclump(6,l)+(specval*speclump)*&
                0.5d0*pp/(thelp*dz(k))
        else
!-- DDMC interior
           help = ((grd_sig(l)+grd_cap(ig,l))*dz(k)+&
                (grd_sig(icnb(6))+grd_cap(ig,icnb(6)))*dz(k+1))*thelp
           grd_opaclump(6,l) = grd_opaclump(6,l)+(specval*speclump)*&
                (2d0/3d0)/(help*dz(k)*thelp)
        endif

     enddo !ig
  enddo !i
  enddo !j
  enddo !k


end subroutine leakage_opacity3
! vim: fdm=marker
