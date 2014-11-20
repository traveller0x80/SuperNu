program supernu

  use mpimod
  use inputparmod
  use timestepmod
  use gridmod
  use gasmod
  use particlemod
  use physconstmod
  use miscmod

  use inputstrmod
  use fluxmod

  use ionsmod, only:ion_read_data,ion_alloc_grndlev
  use bfxsmod, only:bfxs_read_data
  use ffxsmod, only:ffxs_read_data
  use timingmod

  implicit none
!***********************************************************************
! TODO and wishlist:
! - transport[123].f90: no check wl group bounds (drr 2014/11/20)
! - interior_source: source tilting from source derivative (drr 2014/11/20)
!***********************************************************************
  real*8 :: help
  real*8 :: t_elapsed
  integer :: ierr,ns,it,ncell
  integer,external :: memusg
  real*8 :: t0,t1  !timing
!
!-- mpi initialization
  call mpi_init(ierr) !MPI
  call mpi_comm_rank(MPI_COMM_WORLD,impi,ierr) !MPI
  call mpi_comm_size(MPI_COMM_WORLD,nmpi,ierr) !MPI
!
!-- initialize timing module
  call timing_init
!
!--
!-- READ DATA AND INIT SIMULATION
!================================
!-- The setup is done by the master task only, and broadcasted to the
!-- other tasks before packet propagation begins.
!--
  if(impi==impi0) then
    call time(t0)!{{{
!-- startup message
    call banner
!-- read runtime parameters
    call read_inputpars
!-- parse and verify runtime parameters
    call parse_inputpars(nmpi)
!
!-- time step init
    call timestep_init(in_nt,in_ntres,in_alpha,in_tfirst)
!-- constant time step, may be coded to loop if time step is not uniform
    t_elapsed = (in_tlast - in_tfirst) * pc_day  !convert input from days to seconds
    tsp_dt = t_elapsed/in_nt
!
!-- particle init
    ns = in_ns/nmpi
    call particle_init(in_npartmax,ns,in_ns0,in_isimcanlog, &
         in_isddmcanlog,in_tauddmc,in_taulump,in_tauvtime)
!
!-- rand() count and prt restarts
    if(tsp_ntres>1.and..not.in_norestart) then
!-- read rand() count
      call read_restart_randcount
!-- read particle properties
      call read_restart_particles
    endif
!
!-- wlgrid (before grid setup)
    call wlgrid_setup(gas_ng)
    call fluxgrid_setup(in_flx_ndim,in_flx_wlmin,in_flx_wlmax)
!
!-- read input structure
    if(.not.in_noreadstruct.and.in_isvelocity) then
      call read_inputstr(in_igeom,in_ndim)
    else
!== generate_inputstr development in progress
      call generate_inputstr(in_igeom)
    endif

!-- READ DATA
!-- read ion and level data
    call ion_read_data(gas_nelem)  !ion and level data
!-- read bbxs data
    if(.not.in_nobbopac) call read_bbxs_data(gas_nelem)!bound-bound cross section data
!-- read bfxs data
    if(.not.in_nobfopac) call bfxs_read_data           !bound-free cross section data
!-- read ffxs data
    if(.not.in_noffopac) call ffxs_read_data           !free-free cross section data
!
!-- memory statistics
    write(6,*) 'memusg: after setup:',memusg()
!
    call time(t1)
    t_setup = t1-t0!}}}
  endif !impi
!
!-- MPI
  call bcast_permanent !MPI

!-- setup spatial grid
  call grid_init(impi==impi0,gas_ng,gas_wl,in_igeom,in_ndim,in_isvelocity)
  call grid_setup(gas_wl)

  call mpi_setup_communicators(product(in_ndim)) !MPI
!--
  ncell = product(in_ndim)/nmpi_gas
  call scatter_inputstruct(in_ndim,ncell) !MPI

!
!-- setup gas
  if(impi_gas>=0) call gas_init(impi==impi0,ncell)
  if(impi_gas>=0) call gas_setup(impi==impi0)

!
!-- initialize flux tally arrays (rtw: separated from fluxgrid_setup)
  call flux_alloc
!
!-- initial radiation energy
  call initialnumbers

!
!-- allocate arrays of sizes retreived in bcast_permanent
  if(impi_gas>=0) call ion_alloc_grndlev(gas_nelem,gas_ncell)  !ground state occupation numbers
  call particle_alloc(impi==impi0,in_norestart,nmpi)

!
!-- initialize random number generator, use different seeds for each rank
  if(in_nomp==0) stop 'supernu: in_nomp == 0'
  help = rand(in_nomp*impi)
!
!-- reading restart rand() count
  if(tsp_ntres>1.and..not.in_norestart) then
    call scatter_restart_data !MPI
!-- mimicking end of tsp reset
    prt_tlyrand = 0
  else
    prt_tlyrand = 1
  endif
!
!-- instantiating initial particles (if any)
  call initial_particles
!
!
!
!-- time step loop
!=================
  if(impi==impi0) then
     write(6,*)
     write(6,*) "starting time loop:"
     write(6,*) "===================="
  endif
!
  do it=in_ntres,tsp_nt
!-- allow negative and zero it for temperature initialization purposes!{{{
    tsp_it = max(it,1)
!
!-- reset particle clocks
    if(tsp_it<=tsp_ntres) then
      where(.not.prt_isvacant) prt_particles%t = tsp_t
    endif
!
!-- Update tsp_t etc
    call timestep_update(tsp_dt)  !tsp_dt is being set here, any value can be passed
!
!-- updating prt_tauddmc and prt_taulump
    call tau_update

    if(impi==impi0) write(6,'(1x,a,i5,f8.3,"d",i12)') 'timestep:',it, &
         tsp_t/pc_day,count(.not.prt_isvacant)


!-- update all non-permanent variables
    call grid_update(tsp_t)
    if(impi_gas>=0) call gas_update(impi)
!-- energy to be instantiated by source prt_particles per cell in this timestep
    if(impi_gas>=0) call sourceenergy(nmpi)

!
!-- gather from gas workers and broadcast to world ranks
    call bcast_nonpermanent !MPI

!-- grey gamma ray transport
    if(in_srctype=='none' .and. .not.in_novolsrc) then
       call particle_advance_gamgrey
       call allreduce_gammaenergy !MPI
!      grd_edep = grd_emitex  !-- testing: local deposition
       call sourceenergy_gamma
    endif

!-- Calculating gas_emitex from analytic distribution
    call sourceenergy_analytic

!-- Calculating IMC-DDMC albedo coefficients and DDMC leakage opacities
    call leakage_opacity

!-- number of source prt_particles per cell
    call sourcenumbers(nmpi)
!-- Storing vacant "prt_particles" indexes in ordered array "prt_vacantarr"
    allocate(prt_vacantarr(prt_nnew))
    call vacancies
!-- Calculating properties of prt_particles on domain boundary
    call boundary_source
!-- Calculating properties of prt_particles emitted in domain interior
    call interior_source
    
    deallocate(prt_vacantarr)

!-- advance particles
    call particle_advance

!-- collect particle results from all workers
    call reduce_tally !MPI
!
!-- print packet advance load-balancing info
    !if(impi==impi0) write(6,'(1x,a,3(f9.2,"s"))') 'packets time(min|mean|max):',t_pckt_stat
    if(impi==impi0) call timereg(t_pckt_allrank,t_pckt_stat(3))  !register particle advance timing

!-- collect data necessary for restart (tobe written by impi0)
    if(.not.in_norestart) call collect_restart_data !MPI

!-- update temperature
    if(impi_gas>=0) call temperature_update
    call reduce_gastemp !MPI

!
!-- output
    if(impi==impi0) then
!-- luminosity statistics!{{{
      where(flx_lumnum>0) flx_lumdev = ( &
         (flx_lumdev/flx_lumnum - (flx_luminos/flx_lumnum)**2) * &
         flx_lumnum/dble(flx_lumnum - 1) )**.5d0
!-- check energy (particle weight) is accounted
      call energy_check
!-- write output
      if(it>0) call write_output
!
!-- restart writers
      if(.not.in_norestart .and. it>0) then
         call write_restart_file !-- temp
         call write_restart_randcount !-- rand() count
         call write_restart_particles !-- particle properties of current time step
      endif
!!}}}
    endif !impi
!
!-- reset rand counters
    prt_tlyrand = 0
!
!-- write timestep timing to file
    if(it>0) call timing_timestep(impi)
!!}}}
  enddo !tsp_it
!
!
!--
!-- FINISH UP:
!=============
  call mpi_barrier(MPI_COMM_WORLD,ierr) !MPI
!-- Print timing output.
  if(impi==impi0) then
    call time(t1)
    t_all = t1 - t0
    call print_timing                 !print timing results
    write(6,*)
    write(6,*) 'SuperNu finished'
    if(in_grabstdout)write(0,'(a,f8.2,"s")')'SuperNu finished',t_all!repeat to stderr
  endif
!-- Clean up memory. (This help to locate memory leaks)
  call dealloc_all
  call mpi_finalize(ierr) !MPI

end program supernu
