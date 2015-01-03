subroutine transport11(ptcl,ic,ig,isvacant)

  use randommod
  use miscmod
  use gridmod
  use groupmod
  use totalsmod
  use timestepmod
  use physconstmod
  use particlemod
  use inputparmod
  use fluxmod
  implicit none
!
  type(packet),target,intent(inout) :: ptcl
  integer,intent(inout) :: ic, ig
  logical,intent(inout) :: isvacant
!##################################################
!This subroutine passes particle parameters as input and modifies
!them through one IMC transport event (Fleck&Cummings, 1971).  If
!the puretran boolean is set to false, this routine couples to the
!analogous DDMC diffusion routine through the advance.
!##################################################
  real*8,parameter :: cinv = 1d0/pc_c
!
  integer,external :: emitgroup
  real*8 :: r1, r2, thelp,thelpinv
  real*8 :: db, dcol, dcen, dthm, ddop, d
  real*8 :: siglabfact, dcollabfact, elabfact
  real*8 :: rold, P, muold
! real*8 :: x1, x2, xx0
  real*8 :: dtinv
  real*8 :: help
  real*8 :: ppl, ppr

  integer,pointer :: ix
  integer,parameter :: iy=1, iz=1
  real*8,pointer :: r, mu, e, e0, wl
!-- statement function
  integer :: l
  real*8 :: dx
  dx(l) = grd_xarr(l+1) - grd_xarr(l)

  ix => ptcl%ix
  r => ptcl%x
  mu => ptcl%mu
  e => ptcl%e
  e0 => ptcl%e0
  wl => ptcl%wl
!
!-- shortcut
  dtinv = 1d0/tsp_dt

  if(grd_isvelocity) then
     siglabfact = 1d0 - mu*r*cinv
     dcollabfact = tsp_t*(1d0-mu*r*cinv)
     thelp = tsp_t
  else
     siglabfact = 1d0
     dcollabfact = 1d0
     thelp = 1d0
  endif
  thelpinv = 1d0/thelp

!
!== DISTANCE CALCULATIONS
!
!-- distance to boundary = db
  if (ix == 1) then
     db = abs(sqrt(grd_xarr(ix+1)**2-(1d0-mu**2)*r**2)-mu*r)
  elseif (mu < -sqrt(1d0-(grd_xarr(ix)/r)**2)) then
     db = abs(sqrt(grd_xarr(ix)**2-(1d0-mu**2)*r**2)+mu*r)
  else
     db = abs(sqrt(grd_xarr(ix+1)**2-(1d0-mu**2)*r**2)-mu*r)
  endif
!-- sanity check
  if(db/=db) stop 'transport11: db/=db'
!
!-- distance to fictitious collision = dcol
  if(prt_isimcanlog) then
     if(grd_cap(ig,ic)>0d0) then
        r1 = rnd_r(rnd_state)
        prt_tlyrand = prt_tlyrand+1
        dcol = abs(log(r1)/(grd_cap(ig,ic)*dcollabfact))
     else
        dcol = 2d0*abs(pc_c*tsp_dt*thelpinv) !> dcen
     endif
  else
     if((1d0-grd_fcoef(ic))*grd_cap(ig,ic)>0d0) then
        r1 = rnd_r(rnd_state)
        prt_tlyrand = prt_tlyrand+1
        dcol = abs(log(r1)/((1d0-grd_fcoef(ic))*grd_cap(ig,ic)*dcollabfact))
     else
        dcol = 2d0*abs(pc_c*tsp_dt*thelpinv) !> dcen
     endif
  endif
!
!-- distance to Thomson-type collision = dthm
  if(grd_sig(ic)>0d0) then
     r1 = rnd_r(rnd_state)
     prt_tlyrand = prt_tlyrand+1
     dthm = abs(log(r1)/(grd_sig(ic)*dcollabfact))
  else
     dthm = 2d0*abs(pc_c*tsp_dt*thelpinv) !> dcen
  endif
!
!-- distance to census = dcen
  dcen = abs(pc_c*(tsp_t+tsp_dt-ptcl%t)*thelpinv)
!
!-- distance to Doppler shift = ddop
  if(grd_isvelocity.and.ig<grp_ng) then
!      r1 = rnd_r(rnd_state)
!      prt_tlyrand=prt_tlyrand+1
!      ddop = pc_c*tsp_t*(grp_wl(ig+1)-grp_wl(ig))*abs(log(r1))/(grp_wl(ig)*dcollabfact)
!     wl = r1*grp_wl(ig)+(1d0-r1)*grp_wl(ig+1) !uniform sample
!      wl=1d0/(r1*grp_wlinv(ig+1) + (1d0-r1)*grp_wlinv(ig))  !reciprocal sample
!      wl=wl*(1d0-mu*r*cinv)
!      ddop = pc_c*(1d0-mu*r*cinv)*(1d0-wl/(1d0-mu*r*cinv*grp_wl(ig+1)))
!     ddop = pc_c*(1d0-mu*r*cinv)*(1d0-&
!          grp_wl(ig)*log(grp_wl(ig+1)*grp_wlinv(ig))/(grp_wl(ig+1)-grp_wl(ig)))
!     write(*,*) pc_c*(wl*grp_wlinv(ig+1)-1d0)+r*mu
     ddop = abs(pc_c*(1d0-wl*grp_wlinv(ig+1))-r*mu)
  else
     ddop = 2d0*abs(pc_c*tsp_dt*thelpinv) !> dcen
  endif
!
!-- minimum distance = d
  d = min(dcol,dthm,db,dcen,ddop)
  if(d<0d0) stop 'transport11: negative distance'
!
!== END OF DISTANCE CALCULATIONS
!
!-- position, angle, time update  
  rold = r
  r = sqrt((1d0-mu**2)*r**2+(d+r*mu)**2)
!  r = sqrt(r**2+d**2+2d0*d*r*mu)
!
  ptcl%t = ptcl%t + thelp*d*cinv
  muold = mu
  if(r==0d0) then
     mu = 1d0
  else
     mu = (rold*mu+d)/r
  endif

!-- transformation factor set
  if(grd_isvelocity) then
     elabfact = 1d0 - muold*rold*cinv
  else
     elabfact = 1d0
  endif
  !calculating energy deposition and density
  !
  if(.not.prt_isimcanlog) then
        grd_edep(ic) = grd_edep(ic)+e*(1d0-exp(-grd_fcoef(ic) &
             *grd_cap(ig,ic)*siglabfact*d*thelp))*elabfact
     !--
     if(grd_fcoef(ic)*grd_cap(ig,ic)*dx(ix)*thelp>1d-6) then     
        grd_eraddens(ic) = grd_eraddens(ic)+e* &
             (1d0-exp(-grd_fcoef(ic)*siglabfact*grd_cap(ig,ic)*d*thelp))* &
             elabfact/(grd_fcoef(ic)*siglabfact*grd_cap(ig,ic)*pc_c*tsp_dt)
     else
        grd_eraddens(ic) = grd_eraddens(ic)+e* &
             elabfact*d*dcollabfact*cinv*dtinv
     endif
     !--
!     e = e*exp(-grd_fcoef(ic)*grd_cap(ig,ic)*d*dcollabfact)
     e = e*exp(-grd_fcoef(ic)*grd_cap(ig,ic)*siglabfact*d*thelp)

  else
     !
     grd_eraddens(ic) = grd_eraddens(ic)+e* &
          elabfact*d*dcollabfact*cinv*dtinv
  endif

!-- transformation factor reset
  if(grd_isvelocity) then
     elabfact = 1d0 - mu*r*cinv
  else
     elabfact = 1d0
  endif

  !
  if(d == ddop) then !group shift
!     r1 = rnd_r(rnd_state)!{{{
!     prt_tlyrand=prt_tlyrand+1
!-- redshifting
     if(ig<grp_ng) then
        ig = ig+1
!-- lab frame wavelength
!     wl = r1*grp_wl(ig)+(1d0-r1)*grp_wl(ig+1) !uniform sample
!        wl=1d0/(r1*grp_wlinv(ig+1) + (1d0-r1)*grp_wlinv(ig))  !reciprocal sample
!        wl = wl*(1d0-mu*r*cinv)
        wl = (grp_wl(ig)+1d-6*(grp_wl(ig+1)-grp_wl(ig)))*(1d0-mu*r*cinv)
     else
        r1 = rnd_r(rnd_state)
        prt_tlyrand=prt_tlyrand+1
!     wl = r1*grp_wl(grp_ng)+(1d0-r1)*grp_wl(grp_ng+1) !uniform sample
        wl=1d0/(r1*grp_wlinv(grp_ng+1) + (1d0-r1)*grp_wlinv(grp_ng))  !reciprocal sample
        wl = wl*(1d0-mu*r*cinv)
!        wl = grp_wl(grp_ng+1)*(1d0-mu*r*cinv)
     endif
!-- check if ddmc region
     if (((grd_sig(ic)+grd_cap(ig,ic))*dx(ix)* &
          thelp >= prt_tauddmc) &
          .and.(in_puretran.eqv..false.)) then
        ptcl%itype = 2
        grd_methodswap(ic) = grd_methodswap(ic)+1
        if(grd_isvelocity) then
!-- velocity effects accounting
           tot_evelo=tot_evelo+e*r*mu*cinv
!
           e = e*(1d0-r*mu*cinv)
           e0 = e0*(1d0-r*mu*cinv)
           wl = wl/(1d0-r*mu*cinv)
        endif
     else
        ptcl%itype = 1
     endif
!!}}}
  elseif (d == dthm) then  !physical scattering (Thomson-type)
     !!{{{
     r1 = rnd_r(rnd_state)
     prt_tlyrand = prt_tlyrand+1
     mu = 1d0-2d0*r1
     if(abs(mu)<0.0000001d0) then
        mu = 0.0000001d0
     endif
     if(grd_isvelocity) then
        mu = (mu+r*cinv)/(1d0+r*mu*cinv)
!-- velocity effects accounting
        help = 1d0/(1d0-mu*r*cinv)
        tot_evelo=tot_evelo+e*(1d0-elabfact*help)
!
        e = e*elabfact*help
!        e0 = e0*elabfact/(1d0-mu*r*cinv)
        wl = wl*(1d0-mu*r*cinv)/elabfact
     endif
     !
     !!}}}
  elseif (d == dcol) then  !fictitious scattering with implicit capture
     !!{{{
     r1 = rnd_r(rnd_state)
     prt_tlyrand = prt_tlyrand+1
     if(r1<=grd_fcoef(ic).and.prt_isimcanlog) then
        isvacant = .true.
        prt_done = .true.
        grd_edep(ic) = grd_edep(ic) + e*elabfact
!-- velocity effects accounting
        tot_evelo = tot_evelo+e*(1d0-elabfact)
!
     else
        r1 = rnd_r(rnd_state)
        prt_tlyrand = prt_tlyrand+1
        mu = 1d0-2d0*r1
        if(abs(mu)<0.0000001d0) then
           mu = 0.0000001d0
        endif
        if(grd_isvelocity) then
           mu = (mu+r*cinv)/(1d0+r*mu*cinv)
!-- velocity effects accounting
           help = 1d0/(1d0-mu*r*cinv)
           tot_evelo = tot_evelo+e*(1d0-elabfact*help)
!
           e = e*elabfact*help
!           wl = wl*(1d0-mu*r*cinv)/elabfact
           
        endif
!
!-- sample wavelength
        r1 = rnd_r(rnd_state)
        prt_tlyrand = prt_tlyrand+1
        ig = emitgroup(r1,ic)
!
!(rev 121): calculating radiation energy tally per group
        !grd_eraddens(ic)=grd_eraddens(ic)+e*elabfact
!-------------------------------------------------------
! sampling comoving wavelength in group
        r1 = rnd_r(rnd_state)
        prt_tlyrand = prt_tlyrand+1
        wl = 1d0/((1d0-r1)*grp_wlinv(ig)+r1*grp_wlinv(ig+1))
        !wl = (1d0-r1)*grp_wl(ig)+r1*grp_wl(ig+1)
        !wl = 0.5d0*(grp_wl(ig)+grp_wl(ig+1))
        !
        ! sampling sub-group Planck function:
!         x1 = pc_h*pc_c/(grp_wl(ig+1)*pc_kb*grd_temp(ic))
!         x2 = pc_h*pc_c/(grp_wl(ig)*pc_kb*grd_temp(ic))
!         if (x2<pc_plkpk) then
!            bmax = x2**3/(exp(x2)-1d0)
!         elseif (x1>pc_plkpk) then
!            bmax = x1**3/(exp(x1)-1d0)
!         else
!            bmax = pc_plkpk
!         endif
!         r1 = rnd_r(rnd_state)
!                 prt_tlyrand = prt_tlyrand+1
!         r2 = rnd_r(rnd_state)
!                 prt_tlyrand = prt_tlyrand+1
!         xx0 = (1d0-r1)*x1+r1*x2
!         do while (r2>xx0**3/(exp(xx0)-1d0)/bmax)
!            r1 = rnd_r(rnd_state)
!                 prt_tlyrand = prt_tlyrand+1
!            r2 = rnd_r(rnd_state)
!                 prt_tlyrand = prt_tlyrand+1
!            xx0 = (1d0-r1)*x1+r1*x2
!         enddo
!         wl = pc_h*pc_c/(xx0*pc_kb*grd_temp(ic))
        !
        !
        if(grd_isvelocity) then
!-- converting comoving wavelength to lab frame wavelength
           wl = wl*(1d0-r*mu*cinv)
        endif
        if (((grd_sig(ic)+grd_cap(ig,ic))*dx(ix)* &
             thelp >= prt_tauddmc) &
             .and.(in_puretran.eqv..false.)) then
           ptcl%itype = 2
           grd_methodswap(ic) = grd_methodswap(ic)+1
           if(grd_isvelocity) then
!-- velocity effects accounting
              tot_evelo = tot_evelo+e*r*mu*cinv
!
              e = e*(1d0-r*mu*cinv)
              e0 = e0*(1d0-r*mu*cinv)
              wl = wl/(1d0-r*mu*cinv)
           endif
        else
           ptcl%itype = 1
        endif
     endif
     !!}}}
  elseif (d == db) then   !------boundary crossing ----
     if (mu>=0d0) then!{{{
        l = grd_icell(ix+1,iy,iz)
        if (ix == grd_nx) then
!           if(ig/=1) then
           isvacant = .true.
           prt_done = .true.
!
!-- retrieve lab frame flux group
           ig = binsrch(wl,flx_wl,flx_ng+1)
!
!-- check group bounds
           if(ig>flx_ng.or.ig<1) then
              if(ig>flx_ng) then
                 ig=flx_ng
                 wl=flx_wl(flx_ng+1)
              else
                 ig=1
                 wl=flx_wl(1)
              endif
           endif
!
!-- outbound luminosity tally
           tot_eout = tot_eout+e
           flx_luminos(ig,1,1) = flx_luminos(ig,1,1)+e*dtinv
           flx_lumdev(ig,1,1) = flx_lumdev(ig,1,1)+(e*dtinv)**2
           flx_lumnum(ig,1,1) = flx_lumnum(ig,1,1)+1
        ! Checking if DDMC region right
        elseif (((grd_sig(l)+grd_cap(ig,l))*dx(ix+1) &
             *thelp >= prt_tauddmc) &
             .and.(in_puretran.eqv..false.)) then
           r1 = rnd_r(rnd_state)
           prt_tlyrand = prt_tlyrand+1
           if(grd_isvelocity) then
              mu = (mu-r*cinv)/(1d0-r*mu*cinv)
           endif
           help = (grd_cap(ig,l)+grd_sig(l))*dx(ix+1)*thelp
           ppl = 4d0/(3d0*help+6d0*pc_dext)
           P = ppl*(1d0+1.5*abs(mu))
!--
           if (r1 < P) then
              ptcl%itype = 2
              grd_methodswap(ic) = grd_methodswap(ic)+1
              if(grd_isvelocity) then
!-- velocity effects accounting
                 tot_evelo=tot_evelo+e*(1d0-elabfact)
!
                 e = e*elabfact
                 e0 = e0*elabfact
                 wl = wl/elabfact
              endif
              ix = ix+1
              ic = grd_icell(ix,iy,iz)
           else
              r1 = rnd_r(rnd_state)
              prt_tlyrand = prt_tlyrand+1
              r2 = rnd_r(rnd_state)
              prt_tlyrand = prt_tlyrand+1
              mu = -max(r1,r2)
              if(grd_isvelocity) then
                 mu = (mu+r*cinv)/(1d0+r*mu*cinv)
              endif
              r = grd_xarr(ix+1)
           endif
        ! End of check
        else
           r = grd_xarr(ix+1)
           ix = ix+1
           ic = grd_icell(ix,iy,iz)
        endif
     else
        l = grd_icell(ix-1,iy,iz)
        if (ix==1) then
           l = grd_icell(ix+1,iy,iz)
           if (((grd_sig(l)+grd_cap(ig,l))*dx(ix+1) &
                *thelp >= prt_tauddmc) &
                .and.(in_puretran.eqv..false.)) then
              r1 = rnd_r(rnd_state)
              prt_tlyrand = prt_tlyrand+1
              if(grd_isvelocity) then
                 mu = (mu-r*cinv)/(1d0-r*mu*cinv)
              endif
              help = (grd_cap(ig,l)+grd_sig(l))*dx(ix+1)*thelp
              ppl = 4d0/(3d0*help+6d0*pc_dext)
              P = ppl*(1d0+1.5*abs(mu))
              if (r1 < P) then
                 ptcl%itype = 2
                 grd_methodswap(ic) = grd_methodswap(ic)+1
                 if(grd_isvelocity) then
!-- velocity effects accounting
                    tot_evelo=tot_evelo+e*(1d0-elabfact)
!
                    e = e*elabfact
                    e0 = e0*elabfact
                    wl = wl/elabfact
                 endif
                 ix = ix+1
                 ic = grd_icell(ix,iy,iz)
              else
                 r1 = rnd_r(rnd_state)
                 prt_tlyrand = prt_tlyrand+1
                 r2 = rnd_r(rnd_state)
                 prt_tlyrand = prt_tlyrand+1
                 mu = -max(r1,r2)
                 if(grd_isvelocity) then
                    mu = (mu+r*cinv)/(1d0+r*mu*cinv)
                 endif
                 r = grd_xarr(ix+1)
              endif
           else
              r = grd_xarr(ix+1)
              ix = ix+1
              ic = grd_icell(ix,iy,iz)
           endif
        elseif (((grd_sig(l)+grd_cap(ig,l))*dx(ix-1) &
             *thelp >= prt_tauddmc) &
             .and.(in_puretran.eqv..false.)) then
           r1 = rnd_r(rnd_state)
           prt_tlyrand = prt_tlyrand+1
!
!-- amplification factor
           if(grd_isvelocity) then
              mu = (mu-r*cinv)/(1d0-r*mu*cinv)
!
!             e0=e0*(1d0+2d0*min(0.055d0*prt_tauddmc,1d0)*r*cinv)
!             e = e*(1d0+2d0*min(0.055d0*prt_tauddmc,1d0)*r*cinv)
              if(mu<0d0) then
                 help = 1d0/abs(mu)
                 help = min(100d0, help) !-- truncate singularity
!
!-- velocity effects accounting
                 tot_evelo = tot_evelo-e*2d0*(0.55d0*help-1.25d0*abs(mu))*r*cinv
!
!-- apply the excess (higher than factor 2d0) to the energy deposition
                 grd_eamp(ic) = grd_eamp(ic) + &
                    e*2d0*0.55d0*max(0d0,help-2d0)*r*cinv
!-- apply limited correction to the particle
                 help = min(2d0,help)
                 e0 = e0*(1d0+2d0*(0.55d0*help-1.25d0*abs(mu))*r*cinv)
                 e = e*(1d0+2d0*(0.55d0*help-1.25d0*abs(mu))*r*cinv)
              endif
!--
           endif
           help = (grd_cap(ig,l)+grd_sig(l))*dx(ix-1)*thelp
           ppr = 4d0/(3d0*help+6d0*pc_dext)
           P = ppr*(1d0+1.5*abs(mu))
!--
           if (r1 < P) then
              ptcl%itype = 2
              grd_methodswap(ic) = grd_methodswap(ic)+1
              if(grd_isvelocity) then
!-- velocity effects accounting
                 tot_evelo = tot_evelo+e*(1d0-elabfact)
!
                 e = e*elabfact
                 e0 = e0*elabfact
                 wl = wl/elabfact
              endif
              ix = ix-1
              ic = grd_icell(ix,iy,iz)
           else
              r1 = rnd_r(rnd_state)
              prt_tlyrand = prt_tlyrand+1
              r2 = rnd_r(rnd_state)
              prt_tlyrand = prt_tlyrand+1
              mu = max(r1,r2)
              if(grd_isvelocity) then
                 mu = (mu+r*cinv)/(1d0+r*mu*cinv)
              endif
              r = grd_xarr(ix)
           endif
        ! End of check
        else
           r = grd_xarr(ix)
           ix = ix-1
           ic = grd_icell(ix,iy,iz)
        endif
     endif!}}}
  elseif (d == dcen) then
     prt_done = .true.
     grd_numcensus(ic) = grd_numcensus(ic)+1
!     tot_erad = tot_erad + e*elabfact
!
  endif

end subroutine transport11