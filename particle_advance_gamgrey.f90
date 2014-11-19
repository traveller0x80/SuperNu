subroutine particle_advance_gamgrey

  use particlemod
  use timestepmod
  use gridmod
  use physconstmod
  use inputparmod
  use timingmod
  use fluxmod
  implicit none
!##################################################
  !This subroutine propagates all existing particles that are not vacant
  !during a time step.  Particles may generally undergo a physical interaction
  !with the gas, cross a spatial cell boundary, or be censused for continued
  !propagation in the next time step.  Currently DDMC and IMC particle events
  !are being handled in separate subroutines but this may be changed to reduce
  !total subroutine calls in program.
!##################################################
  integer :: ipart, npart, ig
  integer,external :: binsrch
  real*8 :: r1
  integer :: zsrc, iy, iz
  real*8 :: rsrc, musrc, esrc, y, om
  real*8 :: t0,t1  !timing
  real*8 :: labfact,cmffact,x0
  real*8 :: esq,mu0
!-- hardware
!
  type(packet) :: ptcl
!
!-- advection split parameter
  real*8,parameter :: alph2 = .5d0

  logical,parameter :: isshift=.true.

  grd_edep = 0.0
  flx_gamluminos = 0.0
  flx_gamlumdev = 0.0
  flx_gamlumnum = 0
!
!--(rev. 121)
  grd_eraddens = 0d0
!--
  grd_numcensus = 0
  
  call time(t0)

  esq = sum(sqrt(grd_emit))
  grd_nvol = nint(sqrt(grd_emit)/esq*prt_ns)  !-- no source tilting yet
!-- floor under particle per cell number
  where(grd_emit>0d0) grd_nvol = max(grd_nvol,10)
!-- total number of particles
  npart = sum(grd_nvol)

!-- start from the left
  zsrc = 1
  iy = 1
  iz = 1

! Propagating all particles that are not considered vacant: loop
  do ipart = 1, npart
!
!-- find cell in which to generate the particle
     do iz=iz,grd_nz
     do iy=iy,grd_ny
     do zsrc=zsrc,grd_nx
       if(grd_nvol(zsrc,iy,iz)>0) exit  !still particles left to generate
     enddo
     enddo
     enddo
     if(zsrc==grd_nx+1) stop 'prt_adv_gamgrey: particle generation error'
!-- decrease particle-in-cell counter
     grd_nvol(zsrc,iy,iz) = grd_nvol(zsrc,iy,iz) - 1

!-- emission energy per particle
     esrc = grd_emit(zsrc,iy,iz)/grd_nvol(zsrc,iy,iz)

!-- calculating direction cosine (comoving)
     r1 = rand()
     prt_tlyrand = prt_tlyrand+1
     mu0 = 1d0-2d0*r1

!-- particle propagation
     select case(in_igeom)
     case(1)
!-- calculating position
        r1 = rand()
        prt_tlyrand = prt_tlyrand+1
        rsrc = (r1*grd_xarr(zsrc+1)**3 + &
             (1.0-r1)*grd_xarr(zsrc)**3)**(1.0/3.0)
!--
        if(grd_isvelocity) then
           x0 = ptcl%rsrc
           cmffact = 1d0+mu0*x0/pc_c !-- 1+dir*v/c
           musrc = (mu0+x0/pc_c)/cmffact
        else
           musrc = mu0
        endif
     case(2)
        stop 'particle_advance_grey: no 2D'
        y = ptcl%y
        om = ptcl%om
     case(3)
        stop 'particle_advance_gamgray: no 3D transport'
     endselect

     prt_done=.false.

!-- First portion of operator split particle velocity position adjustment
!-- advection
     if(isshift) then
     if ((grd_isvelocity)) then
        select case(in_igeom)
        case(1)
           rsrc = rsrc*tsp_t/(tsp_t+.5*tsp_dt)
           if(rsrc<grd_xarr(zsrc)) then
              zsrc = binsrch(rsrc,grd_xarr,grd_nx+1,0)
           endif
        case(2)
           call advection2(.true.,ig,zsrc,iy,rsrc,y)
        case(3)
           stop 'particle_advance_gamgrey: no 3D transport'
        endselect
     endif
     endif

!     write(*,*) ipart
!-----------------------------------------------------------------------        
!-- Advancing particle until census, absorption, or escape from domain
     select case(in_igeom)

!-- 1D
     case(1)
        do while (.not.prt_done)
           call transport1_gamgrey(ptcl)
!-- transformation factor
           if(grd_isvelocity) then
              labfact = 1.0d0 - musrc*rsrc/pc_c
           else
              labfact = 1d0
           endif
!-- Russian roulette for termination of exhausted particles
           if (esrc<1d-6*ptcl%ebirth .and. .not.prt_done) then
              r1 = rand()
              prt_tlyrand = prt_tlyrand+1
              if(r1<0.5d0) then
                 prt_done = .true.
                 grd_edep(zsrc,iy,iz) = grd_edep(zsrc,iy,iz) + esrc*labfact
!!-- velocity effects accounting
!                 tot_evelo = tot_evelo + esrc*(1d0-labfact)
              else
!!-- weight addition accounted for in external source
!                 tot_eext = tot_eext + esrc
!
                 esrc = 2d0*esrc
                 ptcl%ebirth = 2d0*ptcl%ebirth
              endif
           endif
        enddo

!-- 2D
     case(2)
        stop 'particle_advance_gamgrey: no 2D transport'
!        do while ((.not.prt_done).and.(.not.isvacant))
!           call transport2_gamgrey(ptcl,isvacant)
!!-- transformation factor
!           if(grd_isvelocity) then
!              labfact = 1d0-(musrc*y+sqrt(1d0-musrc**2) * &
!                   cos(om)*rsrc)/pc_c
!           else
!              labfact = 1d0
!           endif
!!-- Russian roulette for termination of exhausted particles
!           if (esrc<1d-6*ptcl%ebirth .and. .not.isvacant) then
!              r1 = rand()
!              prt_tlyrand = prt_tlyrand+1
!              if(r1<0.5d0) then
!                 isvacant = .true.
!                 prt_done = .true.
!                 grd_edep(zsrc,iy,iz) = grd_edep(zsrc,iy,iz) + esrc*labfact
!!!-- velocity effects accounting
!!                 tot_evelo = tot_evelo + esrc*(1d0-labfact)
!              else
!!-- weight addition accounted for in external source
!!                tot_eext = tot_eext + esrc
!!
!                 esrc = 2d0*esrc
!                 ptcl%ebirth = 2d0*ptcl%ebirth
!              endif
!           endif
!        enddo

!-- 3D
     case(3)
        stop 'particle_advance_gamgrey: no 3D transport'
     endselect

!-----------------------------------------------------------------------
!-- advection
     if(isshift) then
     if (grd_isvelocity) then
        select case(in_igeom)
        case(1)
           rsrc = rsrc*(tsp_t + alph2*tsp_dt)/(tsp_t+tsp_dt)
           if(rsrc<grd_xarr(zsrc)) then
              zsrc = binsrch(rsrc,grd_xarr,grd_nx+1,0)
           endif
        case(2)
           call advection2(.false.,ig,zsrc,iy,rsrc,y)
        case(3)
           stop 'particle_advance_gamgrey: no 3D transport'
        endselect
     endif
     endif

  enddo !ipart

  call time(t1)
  t_pckt_stat = t1-t0  !register timing
  call timereg(t_pcktgam, t1-t0)

end subroutine particle_advance_gamgrey