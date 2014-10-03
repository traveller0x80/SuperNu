subroutine analytic_initial

  use gasgridmod
  use inputparmod
  use physconstmod
  use timestepmod
  use manufacmod
  use profiledatamod
  implicit none

  integer :: ig
  real*8 :: trad(gas_nr)

!###############################################
! This subroutines attributes radiation energy to
! each cell and group depeding on user specification
! of gas_srctype
!###############################################
!
  gas_evolinit = 0d0
!
!-- initial radiation energy
  if(in_tradinittype=='prof') then
    if(prof_nttrad==0) stop 'analytic_initial: no trad profile data'
    trad = trad_profile(tsp_t)
    write(6,*) 'Trad applied to initial particles'
  elseif(in_tradinittype=='unif') then
    trad = in_tempradinit
  else
    stop 'analytic_initial: invalid in_tradinittype'
  endif
!
!-- map radiation temperature to gas_evolinit
  if(.not.gas_isvelocity) then
    gas_evolinit = pc_acoef*trad**4 * &
      gas_vals2%volr*(gas_lr)**3
  else
    gas_evolinit = pc_acoef*trad**4 * &
      gas_vals2%volr*(tsp_t*gas_velout)**3
  endif
!--
!
!-- source specific initial conditions (overrides gas_inittyp)
!-- currently only supplying nonzero for gas_srctype=manu
  if(gas_srctype=='none') then
     if(gas_opacanaltype=='pick') then
!-- tstd initial energy profile currently approximation
        stop 'analytic_initial: gas_opacanaltype==pick not implemented'
     else
        return
     endif
  elseif(gas_srctype=='heav') then
     return
  elseif(gas_srctype=='strt') then
     return
  elseif(gas_srctype=='manu') then
     call init_manuprofile(tsp_t)
  else
     stop 'analytic_initial: invalid gas_srctype'
  endif

end subroutine analytic_initial
