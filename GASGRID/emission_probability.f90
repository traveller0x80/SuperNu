subroutine emission_probability

  use inputparmod
  use gasgridmod
  use physconstmod
  use miscmod, only:specint
  implicit none

!-----------------------
  !multigroup volume emission probabilities
!-----------------------

  integer :: i,ig
  real*8 :: x1, x2

!-- init
  gas_emitprob = 0d0

!-- Calculating grouped volume emission probabilities:
  if(in_opacanaltype=='pick') then
     do i=1,gas_ncell
        gas_emitprob(1,i) = in_suolpick1*gas_cap(1,i)/gas_siggrey(i)
        gas_emitprob(2,i) = (1d0 - in_suolpick1)*gas_cap(2,i)/gas_siggrey(i)
!       gas_emitprob(3:gas_ng,i) = 0d0  !-- not necessary
     enddo !i
  else
     if(gas_ng==1) then
        gas_emitprob = 1d0
     else
        do i=1,gas_ncell
           do ig=1,gas_ng
              x1 = pc_h*pc_c/(gas_wl(ig+1)*pc_kb*gas_temp(i))
              x2 = pc_h*pc_c/(gas_wl(ig)*pc_kb*gas_temp(i))
              if(gas_siggrey(i)<=0d0) then
!                gas_emitprob(ig,i) = 0d0  !-- not necessary
              else
                 gas_emitprob(ig,i) = 15d0*specint(x1,x2,3)*gas_cap(ig,i)/ &
                      (gas_siggrey(i)*pc_pi**4)
              endif
           enddo !ig
        enddo !i
     endif
  endif

end subroutine emission_probability
