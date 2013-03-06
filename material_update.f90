SUBROUTINE material_update

  USE gasgridmod
  USE timestepmod
  USE physconstmod
  USE inputparmod
  IMPLICIT NONE

  INTEGER(iknd) :: ir
  REAL(rknd) :: dtemp, Um, expfact, tauNi, tauCo

  gas_emat = 0.0
  DO ir = 1, gas_nr
     dtemp = gas_edep(ir)*3.0/(4.0*pc_pi*gas_dr3arr(ir)*(gas_velno*1.0+gas_velyes*tsp_texp**3))
     dtemp = (dtemp-tsp_dt*gas_fcoef(ir)*gas_sigmap(ir)*pc_c*gas_ur(ir))/gas_bcoef(ir)
     !WRITE(*,*) dtemp
     gas_temp(ir) = gas_temp(ir)+dtemp
     !gas_ur(ir)=dtemp/(tsp_dt*pc_c*gas_sigmap(ir))
     !gas_temp(ir) = (gas_ur(ir)/pc_acoef)**(0.25_rknd)
     !gas_bcoef(ir) = 2.0*pc_acoef*gas_temp(ir)**3
     gas_ur(ir) = pc_acoef*gas_temp(ir)**4
     Um = gas_bcoef(ir)*gas_temp(ir)
     gas_emat = gas_emat + Um*4.0*pc_pi*gas_dr3arr(ir)*(gas_velno*1.0+gas_velyes*tsp_texp**3)/3.0
     !Calculating expansion losses (if any)
     expfact = gas_velno*1.0+gas_velyes*tsp_texp/(tsp_texp+tsp_dt) !(Lr+gas_rarr(gas_nr+1)*tsp_time)/(Lr+gas_rarr(gas_nr+1)*(tsp_time+tsp_dt))
     gas_rhoarr(ir) = gas_rhoarr(ir)*expfact**3
     gas_bcoef(ir) = gas_bcoef(ir)*expfact**3
     !gas_edep(ir) = gas_edep(ir)*3.0/(4.0*pc_pi*gas_dr3arr(ir)*(gas_velno*1.0+gas_velyes*tsp_texp**3))
  ENDDO
  tauCo = 111.3_rknd*86400.0_rknd
  tauNi = 8.8_rknd*86400.0_rknd
  
  nidecay = (1.6022e-6)*1.87*(1.0_rknd-EXP(-(tsp_time+tsp_dt)/tauNi))
  nidecay = nidecay+(1.6022e-6)*1.87*tauCo*(1.0_rknd-EXP(-(tsp_time+tsp_dt)/tauCo))/(tauCo-tauNi)
  nidecay = nidecay-(1.6022e-6)*1.87*(1.0_rknd-EXP(-tsp_time/tauNi))
  nidecay = nidecay-(1.6022e-6)*1.87*tauCo*(1.0_rknd-EXP(-tsp_time/tauCo))/(tauCo-tauNi)
  nidecay = nidecay/tsp_dt
  !WRITE(*,*) nidecay

END SUBROUTINE material_update
