      subroutine gasgrid_update
c     -----------------------
      use mpimod, only:nmpi
      use physconstmod
      use miscmod, only:warn
      use ionsmod
      use timestepmod
      use gasgridmod
      use inputparmod
      use timingmod
      use profiledatamod
      implicit none
************************************************************************
* Update the part of the gas grid that depends on time and temperature.
* The non-changing part is computed in gasgrid_setup.
* The work done here is:
* - nuclear decay (energy release and chemical composition update)
* - temperature and volume
* - LTE EOS: ionization balance and electron density
* - opacities
************************************************************************
      logical :: do_output,lexist,planckcheck
      integer :: i,j,ir,ig,it,istat
      real*8 :: help,x1,x2
      real*8,external :: specint
      real*8 :: dtempfrac = 0.99d0
      real*8 :: dwl(gas_ng)
      real*8 :: natom1fr(gas_nr,-2:-1) !todo: memory storage order?
      real*8 :: natom2fr(gas_nr,-2:-1)
c-- gamma opacity
      real*8,parameter :: ye=.5d0 !todo: compute this value
c-- timing
      real*8 :: t0,t1
c
c-- begin
c
      write(7,*)
      write(7,*) 'update gas grid:'
      write(7,*) '---------------------------'
      if(tsp_it==1) then
       write(6,*)
       write(6,*) 'update gas grid:'
       write(6,*) '---------------------------'
      endif
c
c
      call time(t0)
c
c
c-- nuclear decay
c================
c-- Get ni56 and co56 abundances on begin and end of the time step.!{{{
c-- The difference between these two has decayed.
      if(gas_isvelocity.and.gas_srctype=='none') then
c-- beginning of time step
       help = tsp_t
       call update_natomfr(help)
       forall(i=-2:-1) natom1fr(:,i) = gas_vals2(:)%natom1fr(i)
c-- end of time step
       call update_natomfr(tsp_t + tsp_dt)
       forall(i=-2:-1) natom2fr(:,i) = gas_vals2(:)%natom1fr(i)
c
c-- update the abundances for the center time
       !call update_natomfr(tsp_tcenter)
       call update_natomfr(tsp_t)
c
c-- energy deposition
       gas_vals2(:)%nisource =  !per average atom (mix of stable and unstable)
     &   (natom1fr(:,gas_ini56) - natom2fr(:,gas_ini56)) *
     &    (pc_qhl_ni56 + pc_qhl_co56) +!ni56 that decays adds to co56
     &   (natom1fr(:,gas_ico56) - natom2fr(:,gas_ico56))*pc_qhl_co56
c-- total, units=ergs
       gas_vals2(:)%nisource = gas_vals2(:)%nisource *gas_vals2(:)%natom
c-- use gamma deposition profiles if data available
       if(prof_ntgam>0) then
        help = sum(gas_vals2%nisource)
!       write(6,*) 'ni56 source:',help
        gas_vals2(:)%nisource = help * gamma_profile(tsp_t)
       endif
      endif
!}}}
c
c
c
c-- update volume and density 
c============================
      if(gas_isvelocity) then!{{{
       help = gas_velout*tsp_t
      else
       help = gas_l0+gas_lr
      endif
      !gas_vals2%vol = gas_vals2%volr*(gas_velout*tsp_tcenter)**3 !volume in cm^3
      gas_vals2%vol = gas_vals2%volr*help**3 !volume in cm^3
      gas_vals2%volcrp = gas_vals2%vol !effective volume in cm^3
c
c-- density
      gas_vals2%rho = gas_vals2%mass/gas_vals2%vol
c
c-- keep track of temperature evolution
      gas_temphist(:,tsp_it) = gas_temp!}}}
c
c
c-- update interpolated density and temperatures at cell edges
c=============================================================
!Calculating power law heat capacity
      gas_vals2%bcoef = gas_cvcoef * gas_temp**gas_cvtpwr *
     &  gas_vals2%rho**gas_cvrpwr

c-- add initial thermal input to gas_eext
      if(tsp_it==1) then
       gas_eext = sum(gas_vals2%bcoef*gas_temp*gas_vals2%vol)
      endif
c
c
!     return !DEBUG
c
c
c
c-- opacity
c==========
      calc_opac: if(tsp_it==0) then
c!{{{
c-- gamma opacity
       gas_capgam = in_opcapgam*ye*
     &   gas_vals2(:)%mass/gas_vals2(:)%volcrp
c!}}}
      else calc_opac !tsp_it
c!{{{
c
c-- compute the starting tempurature derivative in the fleck factor
       if(tsp_it==1.or.in_opacanaltype/='none') then
        gas_temp=dtempfrac*gas_temp
        if(gas_isvelocity .and. in_opacanaltype=='none') then
         call eos_update(.false.)
        endif
c
        call analytic_opacity
        if(in_opacanaltype=='none') then
         if(in_ngs==0) then
          call physical_opacity
         else
          call physical_opacity_subgrid
         endif
        endif
c
        gas_siggreyold=gas_siggrey
        gas_temp=gas_temp/dtempfrac
       endif
c
c-- solve LTE EOS
c================
       if(gas_isvelocity) then
        do_output = (in_pdensdump=='each' .or. !{{{
     &    (in_pdensdump=='one' .and. tsp_it==1))
c
        call eos_update(do_output)
        if(tsp_it==1) write(6,'(1x,a27,2(f8.2,"s"))')
     &    'eos timing                :',t_eos !}}}
       endif
c
c
c-- simple physical group/grey opacities: Planck and Rosseland 
       call analytic_opacity
c-- add physical opacities
c-- rtw: must avoid reset in group_opacity routine
       if(in_opacanaltype=='none') then
c-- test existence of input.opac file
        inquire(file='input.opac',exist=lexist)
        if(lexist) then
c-- read in opacities
         open(4,file='input.opac',status='old',iostat=istat)!{{{
         if(istat/=0) stop 'read_opac: no file: input.opac'
c-- read header
         read(4,*,iostat=istat)
         if(istat/=0) stop 'read_opac: file empty: input.opac'
c-- read each cell individually
         do it=1,tsp_it
c-- skip delimiter
          read(4,*,iostat=istat)
          if(istat/=0) stop 'read_opac: delimiter error: input.opac'
c-- read data
          do ir=1,gas_nr
           read(4,*,iostat=istat) help,gas_sig(ir),gas_cap(:,ir)
           if(istat/=0) stop 'read_opac: body error: input.opac'
          enddo !ir
         enddo !it
         close(4)
         write(6,*) 'read_opac: read successfully'
!}}}
        elseif(in_ngs==0) then
c-- calculate opacities
         call physical_opacity
        else
         call physical_opacity_subgrid
        endif
c
c-- copy results into misc arrays
        gas_sigbl = gas_sig
        gas_sigbr = gas_sig
        gas_caprosl = gas_cap
        gas_caprosr = gas_cap
       endif
c
c-- Planck opacity
       planckcheck = (.not.in_nobbopac .or. .not.in_nobfopac .or.
     &   .not.in_noffopac)
!Ryan, why is this conditional (drr 14/05/31)?
       if(planckcheck) then
        gas_siggrey = 0d0
        do ir=1,gas_nr
         do ig=1,gas_ng
          x1 = pc_h*pc_c/(gas_wl(ig + 1)*pc_kb*gas_temp(ir))
          x2 = pc_h*pc_c/(gas_wl(ig)*pc_kb*gas_temp(ir))
          gas_siggrey(ir) = gas_siggrey(ir)+
     &      15d0*gas_cap(ig,ir)*specint(x1,x2,3)/pc_pi**4
         enddo
        enddo
       endif
       !write(*,*) gas_siggrey(1)
       !write(*,*) gas_cap(:,1)
       !gas_siggrey(:)=0.5*gas_cap(2,:)
c
c-- write out opacities
c----------------------
       if(trim(in_opacdump)=='off') then !{{{
c-- do nothing
       else
        open(4,file='output.opac',status='unknown',position='append')
       endif !off
c
c-- write opacity grid
       inquire(4,opened=do_output)
       if(do_output) then
c-- header
        if(tsp_it==1) write(4,'("#",3i8)') gas_ng,gas_nr,tsp_nt
        write(4,'("#",3i8)') tsp_it
c-- body
        do ir=1,gas_nr
         write(4,'(1p,9999e12.4)') gas_temp(ir),gas_sig(ir),
     &     (gas_cap(j,ir),j=1,gas_ng)
        enddo
c-- close file
        close(4)
       endif !do_output !}}}
c
c-- Calculating Fleck factor, leakage opacities
       call fleck_factor(dtempfrac)
c-- Calculating emission probabilities for each group in each cell
       call emission_probability
c-- Calculating IMC-DDMC albedo coefficients and DDMC leakage opacities
       call leakage_opacity
c
c-- timing output
       if(tsp_it==1 .and. tsp_it==1)
     &   write(6,'(1x,a27,3(f8.2,"s"))') 'opacity timing: bb|bf|ff  :',
     &   t_bb(1),t_bf(1),t_ff(1) !}}}
      endif calc_opac !tsp_it
c
c
c
c-- output
c=========
c-- to stdout!{{{
c
c-- energy depots
      if(tsp_it==1) then
       write(6,'(1x,a,1p,e12.4)') 'energy deposition (Lagr)  :',
     &   sum(gas_vals2(:)%nisource)
      endif !tsp_it
c-- totals
      write(7,*)
      write(7,'(1x,a,1p,e12.4)') 'energy deposition (Lagr)  :',
     &  sum(gas_vals2(:)%nisource)
c-- arrays
*     write(7,'(a6,4a12)')'ir','edep/vol','enostor/vol','rho',
      write(7,'(a6,4a12)')'ir','edep/dt','rho',
     &  'nelec','volcrp/vol'
      do i=1,gas_nr,10
       write(7,'(i6,1p,4e12.4)') (j,
     &  gas_vals2(j)%nisource/tsp_dt,
     &  gas_vals2(j)%mass/gas_vals2(j)%vol,
     &  gas_vals2(j)%nelec,gas_vals2(j)%volcrp/gas_vals2(j)%vol,
     &  j=i,min(i+9,gas_nr))
      enddo
!c
!c-- scattering coefficients
!      if(tsp_it>0) then
!       write(7,*)
!       write(7,*) 'sig'
!       write(7,'(1p,10e12.4)') gas_sig
!      endif!}}}
c
c
      call time(t1)
      call timereg(t_gasupd,t1-t0)
c
      end subroutine gasgrid_update
c
c
c
      subroutine update_natomfr(tsince)
c     -------------------------------!{{{
      use physconstmod
      use gasgridmod
      use inputparmod
      implicit none
      real*8,intent(in) :: tsince
************************************************************************
* update natom fractions for nuclear decay
************************************************************************
      real*8 :: expni,expco,help
c
      expni = exp(-tsince/pc_thl_ni56)
      expco = exp(-tsince/pc_thl_co56)
c
c-- update Fe
      help = 1d0 + (pc_thl_co56*expco - pc_thl_ni56*expni)/
     &  (pc_thl_ni56 - pc_thl_co56)
      if(help.lt.0) stop 'update_natomfr: Ni->Fe < 0'
      gas_vals2(:)%natom1fr(26) = gas_vals2(:)%natom0fr(gas_ini56)*help+!initial Ni56
     &  gas_vals2(:)%natom0fr(gas_ico56)*(1d0-expco) +                  !initial Co56
     &  gas_vals2(:)%natom0fr(0)                                        !initial Fe (stable)
c
c-- update Co56 and Co
      help = pc_thl_co56*(expni - expco)/(pc_thl_ni56 - pc_thl_co56)
      if(help.lt.0) stop 'update_natomfr: Ni->Co < 0'
c-- Co56
      gas_vals2(:)%natom1fr(gas_ico56) =
     &  gas_vals2(:)%natom0fr(gas_ini56)*help +  !initial Ni56
     &  gas_vals2(:)%natom0fr(gas_ico56)*expco   !initial Co56
c-- Co
      gas_vals2(:)%natom1fr(27) = gas_vals2(:)%natom1fr(gas_ico56) +  !unstable
     &  gas_vals2(:)%natom0fr(1)                                      !initial Co (stable)
c
c-- update Ni56 and Ni
c-- Ni56
      gas_vals2(:)%natom1fr(gas_ini56) =
     &  gas_vals2(:)%natom0fr(gas_ini56)*expni  !initial Ni56
c-- Ni
      gas_vals2(:)%natom1fr(28) = gas_vals2(:)%natom1fr(gas_ini56) + !unstable
     &  gas_vals2(:)%natom0fr(2)                              !initial Ni (stable)
c!}}}
      end subroutine update_natomfr
