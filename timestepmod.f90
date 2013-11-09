module timestepmod

  implicit none

  integer :: tsp_nt = 0  !total # of time steps
  integer :: tsp_ntres = 0 !restart time step # (at beginning of time step)
  integer :: tsp_it  !current time step number
  real*8 :: tsp_t
  real*8 :: tsp_tcenter
  real*8 :: tsp_dt
  real*8 :: tsp_alpha = 0d0

  save

  contains


  subroutine timestep_init(nt, ntres, alpha, tfirst, dt)
!------------------------------------------------
    use physconstmod
    integer,intent(in) :: nt, ntres
    real*8,intent(in) :: alpha, tfirst, dt
!***********************************************************************
! set the timestep constants
!***********************************************************************
    tsp_nt = nt
    if(ntres<1) then
       tsp_ntres=1
    else
       tsp_ntres=ntres
    endif
    tsp_dt = dt
    tsp_alpha = alpha

!-- beginning of first (restart) time step
    tsp_t = tfirst*pc_day+(tsp_ntres-1)*dt
    tsp_tcenter = tsp_t + .5d0*tsp_dt+(tsp_ntres-1)*dt
!
  end subroutine timestep_init


  subroutine timestep_update(dt)
    implicit none
    real*8,intent(in) :: dt
!***********************************************************************
! update the timestep variables
!***********************************************************************
    tsp_dt = dt
    tsp_t = tsp_t+tsp_dt
    tsp_tcenter = tsp_t + .5*tsp_dt
  end subroutine timestep_update

end module timestepmod
