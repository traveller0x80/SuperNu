subroutine particle_advance

  use particlemod
  use timestepmod
  use gasgridmod
  use physconstmod
  use inputparmod
  use timingmod
  use mpimod
  implicit none

!##################################################
  !This subroutine propagates all existing particles that are not vacant
  !during a time step.  Particles may generally undergo a physical interaction
  !with the gas, cross a spatial cell boundary, or be censused for continued
  !propagation in the next time step.  Currently DDMC and IMC particle events
  !are being handled in separate subroutines but this may be changed to reduce
  !total subroutine calls in program.
!##################################################

  integer*8 :: nddmc, nimc, npckt
  integer :: ipart, ig, zholder, ir,irl,irr
  integer,external :: binsrch
  real*8 :: r1, r2, x1, x2, xx0, bmax, help
  real*8 :: uul, uur, uumax, r0, r3
  integer, pointer :: zsrc, rtsrc !, gsrc
  real*8, pointer :: rsrc, musrc, tsrc, esrc, ebirth, wlsrc
  logical, pointer :: isvacant
  real*8 :: t0,t1  !timing

  logical,parameter :: isshift=.true.

  gas_edep = 0.0
  gas_erad = 0.0
  gas_luminos = 0.0
  gas_lumdev = 0.0
  gas_lumnum = 0
  gas_methodswap = 0
!
!--(rev. 121)
  gas_eraddens =0d0
!--
  gas_numcensus = 0
  
  call time(t0)
  ! Propagating all particles that are not considered vacant: loop
  npckt = 0
  nddmc = 0
  nimc = 0
  do ipart = 1, prt_npartmax
     ! Checking vacancy!{{{
     if (prt_particles(ipart)%isvacant) cycle
     npckt = npckt + 1

     ! Assigning pointers to corresponding particle properties
     zsrc => prt_particles(ipart)%zsrc
     !
     !Ryan W.: Replacing particle group with particle wavelength (rev. 120)
     wlsrc => prt_particles(ipart)%wlsrc
     !gsrc => prt_particles(ipart)%gsrc
     !
     rtsrc => prt_particles(ipart)%rtsrc
     rsrc => prt_particles(ipart)%rsrc
     musrc => prt_particles(ipart)%musrc
     tsrc => prt_particles(ipart)%tsrc
     esrc => prt_particles(ipart)%esrc
     ebirth => prt_particles(ipart)%ebirth
     isvacant => prt_particles(ipart)%isvacant

     prt_done=.false.

     ! Looking up group
     if(rtsrc==1) then
        if(gas_isvelocity) then!{{{
           ig = binsrch(wlsrc/(1d0-rsrc*musrc/pc_c),gas_wl,gas_ng+1,in_ng)
        else
           ig = binsrch(wlsrc,gas_wl,gas_ng+1,in_ng)
        endif
        !
        if(ig>gas_ng.or.ig<1) then
           !particle out of wlgrid energy bound
           if(ig>gas_ng) then
              ig=gas_ng
              if(gas_isvelocity) then
                 wlsrc=gas_wl(gas_ng+1)*(1.0d0-rsrc*musrc/pc_c)
              else
                 wlsrc=gas_wl(gas_ng+1)
              endif
           elseif(ig<1) then
              ig=1
              if(gas_isvelocity) then
                 wlsrc=gas_wl(1)*(1.0d0-rsrc*musrc/pc_c)
              else
                 wlsrc=gas_wl(1)
              endif
           else
              write(*,*) 'domain leak!!'
              prt_done = .true.
              isvacant = .true.
           endif
        endif
        !!}}}
     else
        ig = binsrch(wlsrc,gas_wl,gas_ng+1,in_ng)!{{{
        !
        if(ig>gas_ng.or.ig<1) then
           !particle out of wlgrid bound
           if(ig>gas_ng) then
              ig=gas_ng
              wlsrc=gas_wl(gas_ng+1)
           elseif(ig<1) then
              ig=1
              wlsrc=gas_wl(1)
           else
              write(*,*) 'domain leak!!'
              prt_done = .true.
              isvacant = .true.
           endif
        endif
        !!}}}
     endif

     
     ! Checking if particle conversions are required since prior time step
     if(.not.in_puretran) then
        if(gas_isvelocity) then!{{{
           help = tsp_t
        else
           help = 1d0
        endif
        if ((gas_sig(zsrc)+gas_cap(ig,zsrc))*gas_drarr(zsrc) &
             *help<prt_tauddmc) then
           !write(*,*) 'here', ig, wlsrc, esrc
           if (rtsrc == 2) then
              gas_methodswap(zsrc)=gas_methodswap(zsrc)+1
!-- sampling position uniformly
              r1 =  rand()
              prt_tlyrand = prt_tlyrand+1
              rsrc = (r1*gas_rarr(zsrc+1)**3 + &
                   (1.0-r1)*gas_rarr(zsrc)**3)**(1.0/3.0)
!-- sampling position from source tilt
!               r1 = 0d0
!               r2 = 1d0
!               irl = max(zsrc-1,1)  !-- left neighbor
!               irr = min(zsrc+1,gas_nr)  !-- right neighbor
!               uul = .5d0*(gas_temp(irl)**4 + gas_temp(zsrc)**4)
!               uur = .5d0*(gas_temp(irr)**4 + gas_temp(zsrc)**4)
!               uumax = max(uul,uur)
!               do while (r2 > r1)
!                  r3 = rand()
!                  prt_tlyrand = prt_tlyrand+1
!                  r0 = (r3*gas_rarr(zsrc+1)**3+(1.0-r3)*gas_rarr(zsrc)**3)**(1.0/3.0)
!                  r3 = (r0-gas_rarr(zsrc))/gas_drarr(zsrc)
!                  r1 = (r3*uur+(1d0-r3)*uul)/uumax
!                  r2 = rand()
!                  prt_tlyrand = prt_tlyrand+1
!               enddo
!               rsrc = r0
!
!-- sampling angle isotropically
              r1 = rand()
              prt_tlyrand = prt_tlyrand+1
              musrc = 1.0 - 2.0*r1
              if(gas_isvelocity) then
                 musrc = (musrc + rsrc/pc_c)/(1.0 + rsrc*musrc/pc_c)
!-- velocity effects accounting
                 gas_evelo=gas_evelo+esrc*(1d0-1d0/(1.0 - musrc*rsrc/pc_c))
!
                 esrc = esrc/(1.0 - musrc*rsrc/pc_c)
                 ebirth = ebirth/(1.0 - musrc*rsrc/pc_c)
              endif
                 r1 = rand()
                 prt_tlyrand = prt_tlyrand+1
                 wlsrc = 1d0/(r1/gas_wl(ig+1)+(1d0-r1)/gas_wl(ig))
!              endif
              !
              if(gas_isvelocity) then
                 wlsrc = wlsrc*(1.0-musrc*rsrc/pc_c)
              endif
           endif
           rtsrc = 1
        else
           if(rtsrc==1) then
              if(gas_isvelocity) then
                 gas_evelo = gas_evelo+esrc*musrc*rsrc/pc_c
                 esrc = esrc*(1.0 - musrc*rsrc/pc_c)
                 ebirth = ebirth*(1.0 - musrc*rsrc/pc_c)
                 wlsrc = wlsrc/(1.0 - musrc*rsrc/pc_c)
              endif
              gas_methodswap(zsrc)=gas_methodswap(zsrc)+1
           endif
           rtsrc = 2
        endif!}}}
     endif 
!
!-- looking up group
     if(rtsrc==1) then
        if(gas_isvelocity) then!{{{
           ig = binsrch(wlsrc/(1.0d0-rsrc*musrc/pc_c),gas_wl,gas_ng+1,in_ng)
        else
           ig = binsrch(wlsrc,gas_wl,gas_ng+1,in_ng)
        endif
        if(ig>gas_ng.or.ig<1) then
           !particle out of wlgrid energy bound
           if(ig>gas_ng) then
              ig=gas_ng
              if(gas_isvelocity) then
                 wlsrc=gas_wl(gas_ng+1)*(1.0d0-rsrc*musrc/pc_c)
              else
                 wlsrc=gas_wl(gas_ng+1)
              endif
           elseif(ig<1) then
              ig=1
              if(gas_isvelocity) then
                 wlsrc=gas_wl(1)*(1.0d0-rsrc*musrc/pc_c)
              else
                 wlsrc=gas_wl(1)
              endif
           else
              write(*,*) 'domain leak!!'
              prt_done = .true.
              isvacant = .true.
           endif
        endif
        !!}}}
     else
        ig = binsrch(wlsrc,gas_wl,gas_ng+1,in_ng)!{{{
        !
        if(ig>gas_ng.or.ig<1) then
           !particle out of wlgrid bound
           if(ig>gas_ng) then
              ig=gas_ng
              wlsrc=gas_wl(gas_ng+1)
           elseif(ig<1) then
              ig=1
              wlsrc=gas_wl(1)
           else
              write(*,*) 'domain leak!!'
              prt_done = .true.
              isvacant = .true.
           endif
        endif
        !!}}}
     endif

!-- First portion of operator split particle velocity position adjustment
     if(isshift) then
     if ((gas_isvelocity).and.(rtsrc==1)) then
       call advection1(.true.,isvacant,ig,zsrc,rsrc,musrc,esrc)
     endif
        !
     endif

!     write(*,*) ipart
!-----------------------------------------------------------------------        
     ! Advancing particle until census, absorption, or escape from domain
     do while ((.not.prt_done).and.(.not.isvacant))
        !Calling either diffusion or transport depending on particle type (rtsrc)!{{{
        if (rtsrc == 1.or.in_puretran) then
           nimc = nimc + 1
           call transport1(zsrc,wlsrc,rsrc,musrc,tsrc, &
                esrc,ebirth,rtsrc,isvacant,ipart)
        else
           nddmc = nddmc + 1
           call diffusion1(zsrc,wlsrc,rsrc,musrc,tsrc, &
                esrc,ebirth,rtsrc,isvacant,ipart)
        endif!}}}
     enddo
!-----------------------------------------------------------------------
     !---------------
     !------------

     if(.not.isvacant) then

     ! Redshifting DDMC particle energy weights and wavelengths
     if(rtsrc == 2.and.gas_isvelocity) then
!-- redshifting energy weight!{{{
        gas_evelo=gas_evelo+esrc*(1d0-exp(-tsp_dt/tsp_t))
        esrc = esrc*exp(-tsp_dt/tsp_t)
        ebirth = ebirth*exp(-tsp_dt/tsp_t)
        !
!
!-- find group
        ig = binsrch(wlsrc,gas_wl,gas_ng+1,in_ng)
        !
        if(ig>gas_ng.or.ig<1) then
           !particle out of wlgrid energy bound
           if(ig>gas_ng) then
              ig=gas_ng
           else
              ig=1
           endif
        endif
        !
        !
        if(ig<gas_ng) then
           r1 = rand()
           prt_tlyrand = prt_tlyrand+1
           x1 = gas_cap(ig,zsrc)
           x2 = gas_wl(ig)/(pc_c*tsp_t*(gas_wl(ig+1)-gas_wl(ig)))
           if(r1<x2/(x1+x2)) then
!            if((gas_sig(zsrc)+gas_cap(ig+1,zsrc))*gas_drarr(zsrc) &
!                 *tsp_t>=prt_tauddmc) then
              r1 = rand()
              prt_tlyrand = prt_tlyrand+1
              wlsrc = 1d0/(r1/gas_wl(ig+1)+(1d0-r1)/gas_wl(ig))
              wlsrc = wlsrc*exp(tsp_dt/tsp_t)
!            endif
           endif
        endif
        !!}}}
     endif

     endif

     ! Looking up group
     if(rtsrc==1) then
        if(gas_isvelocity) then!{{{
           ig = binsrch(wlsrc/(1.0d0-rsrc*musrc/pc_c),gas_wl,gas_ng+1,in_ng)
        else
           ig = binsrch(wlsrc,gas_wl,gas_ng+1,in_ng)
        endif
        if(ig>gas_ng.or.ig<1) then
           !particle out of wlgrid energy bound
           if(ig>gas_ng) then
              ig=gas_ng
              if(gas_isvelocity) then
                 wlsrc=gas_wl(gas_ng+1)*(1.0d0-rsrc*musrc/pc_c)
              else
                 wlsrc=gas_wl(gas_ng+1)
              endif
           elseif(ig<1) then
              ig=1
              if(gas_isvelocity) then
                 wlsrc=gas_wl(1)*(1.0d0-rsrc*musrc/pc_c)
              else
                 wlsrc=gas_wl(1)
              endif
           else
              write(*,*) 'domain leak!!'
              prt_done = .true.
              isvacant = .true.
           endif
        endif
        !!}}}
     else
        ig = binsrch(wlsrc,gas_wl,gas_ng+1,in_ng)!{{{
        !
        if(ig>gas_ng.or.ig<1) then
           !particle out of wlgrid bound
           if(ig>gas_ng) then
              ig=gas_ng
              wlsrc=gas_wl(gas_ng+1)
           elseif(ig<1) then
              ig=1
              wlsrc=gas_wl(1)
           else
              write(*,*) 'domain leak!!'
              prt_done = .true.
              isvacant = .true.
           endif
        endif
        !!}}}
     endif
     
     if(isshift) then
     if ((gas_isvelocity).and.(rtsrc==1)) then
       call advection1(.false.,isvacant,ig,zsrc,rsrc,musrc,esrc)
     endif
     endif

     if(.not.isvacant) then
!
!-- radiation energy at census
     if(gas_isvelocity) then
        if(rtsrc==2) then
           gas_erad = gas_erad + esrc
        else
           gas_erad = gas_erad + esrc !*(1d0-musrc*rsrc/pc_c)
!-- velocity effects accounting
!           gas_evelo=gas_evelo+esrc*musrc*rsrc/pc_c
!
        endif
     else
        gas_erad = gas_erad + esrc
     endif

     endif

  enddo !ipart

  call time(t1)
  t_pckt_stat = t1-t0  !register timing
  call timereg(t_pckt, t1-t0)
  call timereg(t_pcktnpckt, dble(npckt))
  call timereg(t_pcktnddmc, dble(nddmc))
  call timereg(t_pcktnimc, dble(nimc))
  npckt = 0
  nddmc = 0
  nimc = 0
  !write(6,*) eleft, eright

  gas_eext = gas_eext-gas_eleft-gas_eright

end subroutine particle_advance


              !wlsrc = 0.5d0*(gas_wl(ig)+gas_wl(ig+1))
              !r1 = rand()
!           prt_tlyrand = prt_tlyrand+1
              !wlsrc=gas_wl(ig)*(1d0-r1)+gas_wl(ig+1)*r1
              !
!               r1 = rand()
!           prt_tlyrand = prt_tlyrand+1
!               if(r1<gas_cap(ig,zsrc)/(gas_cap(ig,zsrc)+gas_sig(zsrc))) then
!                  x1 = pc_h*pc_c/(gas_wl(ig+1)*pc_kb*gas_temp(zsrc))
!                  x2 = pc_h*pc_c/(gas_wl(ig)*pc_kb*gas_temp(zsrc))
!                  if (x2<pc_plkpk) then
!                     bmax = x2**3/(exp(x2)-1d0)
!                  elseif (x1>pc_plkpk) then
!                     bmax = x1**3/(exp(x1)-1d0)
!                  else
!                     bmax = pc_plkpk
!                  endif
!                  r1 = rand()
!           prt_tlyrand = prt_tlyrand+1
!                  r2 = rand()
!           prt_tlyrand = prt_tlyrand+1
!                  xx0 = (1d0-r1)*x1+r1*x2
!                  do while (r2>xx0**3/(exp(xx0)-1d0)/bmax)
!                     r1 = rand()
!           prt_tlyrand = prt_tlyrand+1
!                     r2 = rand()
!           prt_tlyrand = prt_tlyrand+1
!                     xx0 = (1d0-r1)*x1+r1*x2
!                  enddo
!                  wlsrc = pc_h*pc_c/(xx0*pc_kb*gas_temp(zsrc))
!               else
