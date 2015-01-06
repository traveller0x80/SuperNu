program supernu

  use randommod
  use mpimod
  use inputparmod
  use timestepmod
  use groupmod
  use gridmod
  use gasmod
  use particlemod
  use physconstmod
  use miscmod
  use totalsmod

  use inputstrmod
  use fluxmod

  use ionsmod, only:ion_read_data,ion_alloc_grndlev
  use bfxsmod, only:bfxs_read_data
  use ffxsmod, only:ffxs_read_data
  use timingmod

  implicit none
!***********************************************************************
! TODO and wishlist:
!***********************************************************************
  real*8 :: help
  real*8 :: t_elapsed
  integer :: ierr,ns,nmax,it
  integer :: icell1,ncell !number of cells per rank (gas_ncell)
  real*8 :: t0,t1 !timing
  character(15) :: msg
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
     t0 = t_time()!{{{
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
     nmax = in_prt_nmax/nmpi
     call particle_init(nmax,ns,in_ns0,in_isimcanlog, &
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
     call group_init(in_ng,in_wldex,in_wlmin,in_wlmax)
     call fluxgrid_setup(in_flx_ndim,in_flx_wlmin,in_flx_wlmax)
!
!-- read input structure
     if(.not.in_noreadstruct.and.in_isvelocity) then
       call read_inputstr(in_igeom,in_ndim,in_voidcorners,nmpi)
     else
!== generate_inputstr development in progress
       call generate_inputstr(in_igeom)
     endif
!-- compressed domain, serialize non-void cells
     call inputstr_compress

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
     msg = 'post read:'
     write(6,*) 'memusg: ',msg,memusg()
!
     t1 = t_time()
     t_setup = t1-t0!}}}
  endif !impi

!-- broadcast init info from impi0 rank to all others
  call bcast_permanent !MPI


!-- setup spatial grid
  call grid_init(impi==impi0,grp_ng,in_igeom,in_ndim,str_nc,str_lvoid,in_isvelocity)
!-- domain-decompose input structure
  call scatter_inputstruct(in_ndim,icell1,ncell) !MPI
  call grid_setup

!-- setup gas
  call gas_init(impi==impi0,icell1,ncell,grp_ng)
  call gas_setup(impi)
!-- inputstr no longer needed
  call inputstr_dealloc


!-- allocate flux arrays
  call flux_alloc


!-- initial radiation energy
  call initialnumbers

!-- allocate arrays of sizes retreived in bcast_permanent
  call ion_alloc_grndlev(gas_nelem,gas_ncell)  !ground state occupation numbers
  call particle_alloc(impi==impi0,in_norestart,nmpi)

!-- initialize random number generator, use different seeds for each rank
  if(in_nomp==0) stop 'supernu: in_nomp == 0'
  call rnd_seed(rnd_state,in_nomp*impi)

!-- reading restart rand() count
  if(tsp_ntres>1.and..not.in_norestart) then
     call scatter_restart_data !MPI
     prt_tlyrand = 0 !mimicking end of tsp reset
  else
     prt_tlyrand = 1
  endif

!-- instantiating initial particles (if any)
  call initial_particles



!-- time step loop
!=================
  if(impi==impi0) then
     msg = 'post setup:'
     write(6,*) 'memusg: ',msg,memusg()
!
     write(6,*)
     write(6,*) "starting time loop:"
     write(6,*) "===================="
  endif
!
  do it=in_ntres,tsp_nt
     t_timelin(1) = t_time() !timeline!{{{
!-- allow negative and zero it for temperature initialization purposes
     tsp_it = max(it,1)

!-- Update tsp_t etc
     call timestep_update(tsp_dt)  !tsp_dt is being set here, any value can be passed
     call tau_update !updating prt_tauddmc and prt_taulump

!-- write timestep
     help = merge(tot_eerror,tot_erad,it>1)
     if(impi==impi0) write(6,'(1x,a,i5,f8.3,"d",i10,1p,2e10.2)') 'timestep:', &
        it,tsp_t/pc_day,count(.not.prt_isvacant),help

!-- update all non-permanent variables
     call grid_update(tsp_t)
     call gas_update(impi,it)
     call sourceenergy(nmpi) !energy to be instantiated per cell in this timestep
     call mpi_barrier(MPI_COMM_WORLD,ierr) !MPI


!-- grey gamma ray transport
     t_timelin(2) = t_time() !timeline
     if(in_srctype=='none' .and. .not.in_novolsrc) then
        call allgather_gammacap
        call particle_advance_gamgrey(nmpi)
        call allreduce_gammaenergy !MPI
!-- testing: local deposition
!       grd_edep = grd_emitex
!-- testing: dump integral numbers
!       if(impi==impi0) write(6,*) 'source:', &
!          sum(grd_emitex),sum(grd_edep),sum(grd_edep)/sum(grd_emitex)
     else
        grd_edep = 0d0
     endif

!-- gather from gas workers and broadcast to world ranks
     t_timelin(3) = t_time() !timeline
     call bcast_nonpermanent !MPI
     call sourceenergy_misc

     call sourceenergy_analytic !gas_emitex from analytic distribution
     call leakage_opacity       !IMC-DDMC albedo coefficients and DDMC leakage opacities
     call emission_probability !emission probabilities for ep-group in each cell
     call sourcenumbers         !number of source prt_particles per cell

     t_timelin(4) = t_time() !timeline
     if(prt_nnew>0) then
        allocate(prt_vacantarr(prt_nnew))
        call vacancies             !Storing vacant "prt_particles" indexes in ordered array "prt_vacantarr"
        call boundary_source       !properties of prt_particles on domain boundary
        call interior_source       !properties of prt_particles emitted in domain interior
        deallocate(prt_vacantarr)
     endif
     if(tsp_it<=tsp_ntres) where(.not.prt_isvacant) prt_particles%t = tsp_t !reset particle clocks

!-- advance particles
     t_timelin(5) = t_time() !timeline
     call particle_advance
     t_timelin(6) = t_time() !timeline
     call mpi_barrier(MPI_COMM_WORLD,ierr) !MPI
     call reduce_tally !MPI !collect particle results from all workers

!-- print packet advance load-balancing info
     !if(impi==impi0) write(6,'(1x,a,3(f9.2,"s"))') 'packets time(min|mean|max):',t_pckt_stat
     if(impi==impi0) then
        call timereg(t_pcktmin,t_pckt_stat(1))
        call timereg(t_pcktmea,t_pckt_stat(2))
        call timereg(t_pcktmax,t_pckt_stat(3))
     endif

!-- collect data necessary for restart (tobe written by impi0)
     if(.not.in_norestart) call collect_restart_data !MPI

!-- update temperature
     call temperature_update
     call reduce_gastemp !MPI

!-- output
     if(impi==impi0) then
!-- luminosity statistics!{{{
        where(flx_lumnum>0) flx_lumdev = ( &
           (flx_lumdev/flx_lumnum - (flx_luminos/flx_lumnum)**2) * &
           flx_lumnum/dble(flx_lumnum - 1) )**.5d0
!
!-- total energy startup values and energy conservation
        if(it<1) call totals_startup
        call totals_error !check energy (particle weight) is accounted

!-- write output
        if(it>0) call write_output
!-- restart writers
        if(.not.in_norestart .and. it>0) then
           call write_restart_file !temp
           call write_restart_randcount !rand() count
           call write_restart_particles !particle properties of current time step
        endif
!!}}}
     endif !impi

!-- reset rand counters
     prt_tlyrand = 0

!-- write timestep timing to file
     if(it>0) call timing_timestep(impi)
     t_timelin(7) = t_time() !timeline
     t_timeline(:6) = t_timeline(:6) + (t_timelin(2:) - t_timelin(:6))
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
!
!-- print memory usage
     msg = 'post loop:'
     write(6,*)
     write(6,*) 'memusg: ',msg,memusg()

!-- print cpu timing usage
     t1 = t_time()
     t_all = t1 - t0
     call print_timing  !print timing results
     write(6,*)
     write(6,*) 'SuperNu finished'
     if(in_grabstdout) write(0,'(a,f8.2,"s")')'SuperNu finished',t_all!repeat to stderr
  endif
!-- Clean up memory. (This helps to locate memory leaks)
  call dealloc_all
  call mpi_finalize(ierr) !MPI

end program supernu
