module particlemod

  implicit none

  !Ryan W.: Changing group attribute to continuous wavelength (rev. 120)
  type packet
     sequence
     integer :: zsrc, rtsrc !,gsrc
     real*8 :: rsrc, musrc, tsrc
     real*8 :: esrc, ebirth, wlsrc
     logical :: isvacant
  end type packet
  type(packet), dimension(:), pointer :: prt_particles  !(prt_npartmax)
!
  integer :: prt_npartmax, prt_ns, prt_ninit
  integer :: prt_nsurf, prt_nexsrc, prt_nnew, prt_ninitnew
!-- rtw: random number counter added (rev. 262). associated with particle routines
  integer :: prt_tlyrand
!-- rtw: array of rand counts from each rank
  integer, allocatable :: prt_tlyrandarr(:)
!-- particle property restart arrays:
  logical, allocatable :: prt_tlyvacant(:,:)
  integer, allocatable :: prt_tlyzsrc(:,:), prt_tlyrtsrc(:,:)
  real*8, allocatable :: prt_tlyrsrc(:,:), prt_tlymusrc(:,:), prt_tlytsrc(:,:)
  real*8, allocatable :: prt_tlyesrc(:,:), prt_tlyebirth(:,:), prt_tlywlsrc(:,:)
!
  integer, allocatable :: prt_vacantarr(:) !array of vacant particle array locations

  logical :: prt_done
  logical :: prt_isimcanlog !sets flux tally and energy deposition ...
  !to analog in IMC
  logical :: prt_isddmcanlog !sets flux tally and energy deposition ...
  !to analog in DDMC

  real*8 :: prt_tauddmc

  save

  contains

  subroutine particle_init(npartmax,ns,ninit,isimcanlog,isddmcanlog,tauddmc,nummespasint)
!--------------------------------------
    integer,intent(in) :: npartmax, ns, ninit, nummespasint
    logical,intent(in) :: isimcanlog, isddmcanlog
    real*8,intent(in) :: tauddmc
!***********************************************************************
! init particle module
!***********************************************************************
!
!-- adopt input values in module internal storage
    prt_npartmax = npartmax
    prt_ns = ns
    prt_ninit = ninit
    prt_isimcanlog = isimcanlog
    prt_isddmcanlog = isddmcanlog
    prt_tauddmc = tauddmc
!
!-- allocate permanent storage (dealloc in dealloc_all.f)
    allocate(prt_particles(prt_npartmax))
    prt_particles%isvacant = .true.
!-- rand() count per rank allocation
    allocate(prt_tlyrandarr(nummespasint))
    prt_tlyrandarr = 0
!-- mpi gather arrays for particles
    allocate(prt_tlyvacant(nummespasint,npartmax))
    allocate(prt_tlyzsrc(nummespasint,npartmax))
    allocate(prt_tlyrtsrc(nummespasint,npartmax))
    allocate(prt_tlyrsrc(nummespasint,npartmax))
    allocate(prt_tlymusrc(nummespasint,npartmax))
    allocate(prt_tlytsrc(nummespasint,npartmax))
    allocate(prt_tlyesrc(nummespasint,npartmax))
    allocate(prt_tlyebirth(nummespasint,npartmax))
    allocate(prt_tlywlsrc(nummespasint,npartmax))
!
  end subroutine particle_init

end module particlemod
