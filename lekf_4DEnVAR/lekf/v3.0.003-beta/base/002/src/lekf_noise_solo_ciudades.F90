!###############################################################################
!
! filter noise
!
! colored noise with zero mean, std.dev. s, and time correlation tau :
!
!   g(t)           ~ N(mu,sigma**2)
!
!   E[g(t)g(t+dt)] = exp( - |dt|/tau ) = alfa(dt)
!
! implemented with:
!
!   g(t+dt) = mu + alfa(dt) [g(t)-mu] + sqrt(1-alfa(dt)**2) sigma w(t)
!
!
!###############################################################################
!
#define TRACEBACK write (gol,'("in ",a," (",a,", line",i5,")")') rname, __FILE__, __LINE__; call goErr
#define IF_NOTOK_RETURN(action) if (status/=0) then; TRACEBACK; action; return; end if
#define IF_ERROR_RETURN(action) if (status> 0) then; TRACEBACK; action; return; end if
!
#include "lekf.inc"
!
!###############################################################################

module LEKF_Noise

  use GO, only : gol, goPr, goErr
  
  implicit none
  
  ! --- in/out --------------------------
  
  private

  public  ::  nnoise, noise_namelen, noise_name
  public  ::  nhist

  public  ::  disturb_factor
  public  ::  noise_mini, noise_maxi

  public  ::  LEKF_Noise_Init, LEKF_Noise_Done
  public  ::  SetDC, ResetDC
  public  ::  SetDC_Means
  public  ::  ClipDC
  public  ::  GetNoiseApply


  ! --- const ------------------------------

  character(len=*), parameter   ::  mname = 'LEKF_Noise'

  ! maximum number of noise elements:
  integer, parameter              ::  maxnoise = 10

  ! maximum length of description:
  integer, parameter              ::  noise_namelen = 32

  ! size of the noise history
  integer, parameter :: nhist   = 2   ! <-- minimum value
  !integer, parameter :: nhist   = 8
  
  ! --- var -----------------------------
  
  ! actual number of noise elements:
  integer                         ::  nnoise
    
  ! noise description
  character(len=noise_namelen)    ::  noise_name(maxnoise)
  
  ! noise parameters:
  real                            ::  noise_mu      (maxnoise)
  real                            ::  noise_sigma   (maxnoise)
  real, allocatable               ::  noise_tau_days(:,:,:) ! (nx,ny,nnoise)
  real                            ::  noise_mini    (maxnoise)
  real                            ::  noise_maxi    (maxnoise)
  ! disturb parameters:
  real                            ::  disturb_factor(maxnoise)
  

contains

  
  ! =============================================
  
  
  subroutine LEKF_Noise_Init( rcF, status )
  
    use GO, only : TrcFile
    use GO, only : goSplitString
    use Dims, only : nx, ny
    
    ! --- in/out ---------------------------------
    
    type(TrcFile), intent(in)       ::  rcF
    integer, intent(out)            ::  status
    
    ! --- const ----------------------------------

    character(len=*), parameter   ::  rname = mname//'/LEKF_Noise_Init'
    
    ! --- local ----------------------------------
    
    character(len=512)    ::  key
    integer               ::  inoise
    real                  ::  noise_tau_days_read
    character(len=512)    ::  noise_tau_days_file
    character(len=512)    ::  noise_tau_days_variable
    
    ! --- begin ----------------------------------
    
    ! info ...
    write (gol,'("init noise ...")'); call goPr
    
    ! read noise names:
    call rcF%Get( 'kf.noise.names', key, status )
    IF_NOTOK_RETURN(status=1)
    
    ! split:
    call goSplitString( trim(key), nnoise, noise_name, status )
    IF_NOTOK_RETURN(status=1)
    
    ! allocate noise array:
    allocate( noise_tau_days(nx,ny,nnoise), stat=status )  
    IF_NOTOK_RETURN(status=1) 

    ! loop over noise elements:
    do inoise = 1, nnoise
      ! info ...
      write (gol,'("  setup `",a,"` ...")') trim(noise_name(inoise)); call goPr
      ! mean:
      call rcF%Get( 'kf.noise.'//trim(noise_name(inoise))//'.mu', noise_mu(inoise), status )
      IF_NOTOK_RETURN(status=1)
      ! std.dev.:
      call rcF%Get( 'kf.noise.'//trim(noise_name(inoise))//'.sigma', noise_sigma(inoise), status )
      IF_NOTOK_RETURN(status=1)
      ! info ...
      write (gol,'("    mu    : ",f8.2)') noise_mu(inoise); call goPr
      write (gol,'("    sigma : ",f8.2)') noise_sigma(inoise); call goPr

      call rcF%Get( 'kf.noise.'//trim(noise_name(inoise))//'.tau_days.file', noise_tau_days_file, status )
      IF_NOTOK_RETURN(status=1)
      ! replace with field from file ?
      if ( len_trim(noise_tau_days_file) > 0 ) then
        ! variable name:
        call rcF%Get( 'kf.noise.'//trim(noise_name(inoise))//'.tau_days.variable', noise_tau_days_variable, status )
        IF_NOTOK_RETURN(status=1)
        ! info ...
        write (gol,'("    read tau field ...")'); call goPr
        write (gol,'("      file     : ",a)') trim(noise_tau_days_file); call goPr
        write (gol,'("      variable : ",a)') trim(noise_tau_days_variable); call goPr
	      ! read from file:
        call Read_Noise_tau_days( noise_tau_days_file, noise_tau_days_variable, inoise, status )
        IF_NOTOK_RETURN(status=1)
      else
        ! temporal correlation period:
        call rcF%Get( 'kf.noise.'//trim(noise_name(inoise))//'.tau_days', noise_tau_days_read, status )
        IF_NOTOK_RETURN(status=1)
        ! info ..
        write (gol,'("    tau   : ",f8.2," days")') noise_tau_days_read; call goPr
        ! fill default:
        noise_tau_days(:,:,inoise) = noise_tau_days_read
      end if

      ! minimum:
      call rcF%Get( 'kf.noise.'//trim(noise_name(inoise))//'.mini', noise_mini(inoise), status )
      IF_NOTOK_RETURN(status=1)
      ! maximum:
      call rcF%Get( 'kf.noise.'//trim(noise_name(inoise))//'.maxi', noise_maxi(inoise), status )
      IF_NOTOK_RETURN(status=1)
      ! info ..
      write (gol,'("    range : ",f8.2," - ",f8.2)') noise_mini(inoise), noise_maxi(inoise); call goPr

      ! disturb factor:
      call rcF%Get( 'kf.noise.'//trim(noise_name(inoise))//'.disturb.factor', disturb_factor(inoise), status )
      IF_NOTOK_RETURN(status=1)
      ! info ..
      write (gol,'("    disturb factor : ",f8.2)') disturb_factor(inoise); call goPr

    end do
    
    ! ok
    status = 0
    
  end subroutine LEKF_Noise_Init
  
  
  ! ***
  
  
  subroutine LEKF_Noise_Done( status )
  
    ! --- in/out ---------------------------------
    
    integer, intent(out)            ::  status
    
    ! --- const ----------------------------------

    character(len=*), parameter   ::  rname = mname//'/LEKF_Noise_Done'

    ! --- local ----------------------------------
    
    ! --- begin ----------------------------------
    
    ! done with noise array
    deallocate( noise_tau_days )

    ! ok
    status = 0
    
  end subroutine LEKF_Noise_Done
  
  
  ! ***
  
  
  subroutine SetDC_Means( dc, status )

    ! --- in/out -------------------------------
    
    real, intent(inout)               ::  dc(:,:,:)  ! (nx,ny,nnoise)
    integer, intent(out)              ::  status
    
    ! --- const ---------------------------------
    
    character(len=*), parameter   ::  rname = mname//'/SetDC_Means'
    
    ! --- local --------------------------------
    
    integer       ::  inoise
    
    ! --- begin --------------------------------
    
    ! loop over noise parameters:
    do inoise = 1, nnoise
      ! set to mean values:
      dc(:,:,inoise) = noise_mu(inoise)
    end do
    
    ! ok
    status = 0
    
  end subroutine SetDC_Means
  
  
  ! ***
  
  
  subroutine ClipDC( dc, status )

    ! --- in/out -------------------------------
    
    real, intent(inout)               ::  dc(:,:,:,:)  ! (nx,ny,nnoise,nhist)
    integer, intent(out)              ::  status
    
    ! --- const ---------------------------------
    
    character(len=*), parameter   ::  rname = mname//'/ClipDC'
    
    ! --- local --------------------------------
    
    integer       ::  inoise
    
    ! --- begin --------------------------------
    
    ! loop over noise parameters:
    do inoise = 1, nnoise
      ! truncate to [mini,maxi] :
      dc(:,:,inoise,:) = max( noise_mini(inoise), dc(:,:,inoise,:)                     )
      dc(:,:,inoise,:) = min(                     dc(:,:,inoise,:), noise_maxi(inoise) )
    end do
    
    ! ok
    status = 0
    
  end subroutine ClipDC


  ! ***
  
  
  subroutine Read_Noise_tau_days( infile, varname, inoise, status )
  
    !use dims          , only : nx, ny
    !use Grid, only : TllGridInfo, Init, Done, FillGrid_AreaAverage
    use LE_Grid       , only : ugg
    use C3PO          , only : T_File_Ugg, T_Grid_Ugg
    use LE_Data_Common, only : Grid_Convertors

    !use MDF,  only : MDF_Open, MDF_Close, MDF_NETCDF, MDF_READ
    !use MDF,  only : MDF_Inq_DimID, MDF_Inquire_Dimension
    !use MDF,  only : MDF_Inq_VarID, MDF_Get_Var

    ! --- in/out ---------------------------------
    
    character(len=*), intent(in)    ::  infile
    character(len=*), intent(in)    ::  varname
    integer, intent(in)             ::  inoise
    integer, intent(out)            ::  status
    
    ! --- const ----------------------------------

    character(len=*), parameter   ::  rname = mname//'/LEKF_Noise_Init'
    
    ! --- local ----------------------------------
    
    type(T_File_Ugg)      ::  file_in
    character(len=1024)   ::  description
    integer               ::  varid
    type(T_Grid_Ugg)      ::  grid_in
    !integer           ::  nlon, nlat
    !integer           ::  ncid, dimid, varid
    !real, allocatable ::  lons(:), lats(:)
    real, allocatable     ::  noise_tau_days_read(:,:)
    character(len=64)     ::  units
    !type(TllGridInfo) ::  lli_noise
    
    ! --- begin ----------------------------------
    
    ! open file:
    call file_in%Open( trim(infile), status )
    IF_NOTOK_RETURN(status=1)

    ! variable description:
    description = 'var_name='//trim(varname)
    ! variable id:
    call file_in%Inq_VarID( trim(description), varid, status )
    IF_NOTOK_RETURN(status=1)
    ! init grid definition
    call file_in%Get_Grid( varid, grid_in, status )
    IF_NOTOK_RETURN(status=1)

    ! storage for temporal length scales:
    allocate( noise_tau_days_read(grid_in%nlon,grid_in%nlat), stat=status )
    IF_NOTOK_RETURN(status=1)
    ! read:
    call file_in%Get_Var( trim(description), noise_tau_days_read, units, status, &
                           start=(/1,1/), count=(/grid_in%nlon,grid_in%nlat/) )
    IF_NOTOK_RETURN(status=1)

    ! regrid:
    call Grid_Convertors%Ugg_AreaAver( grid_in, noise_tau_days_read, &
                                         ugg, noise_tau_days(:,:,inoise), status )
    IF_NOTOK_RETURN(status=1)

    ! clear:
    call grid_in%Done(status)
    IF_NOTOK_RETURN(status=1)
    ! close:
    call file_in%Close( status )
    IF_NOTOK_RETURN(status=1)

    ! ok
    status = 0
  
  end subroutine Read_Noise_tau_days
  
  
  ! ***
  
  
  subroutine SetDC( dc, ind, rnd, status, dt_days )

    use Num      , only : T_Random
    use LEKF_dims, only : nx, ny

    ! --- in/out -------------------------------
    
    real, intent(inout)               ::  dc(nx,ny,nnoise,nhist)
    integer, intent(in)               ::  ind
    type(T_Random), intent(inout)     ::  rnd
    integer, intent(out)              ::  status
    
    real, intent(in), optional  ::  dt_days !, tau   ! same units !
    
    ! --- const ---------------------------------
    
    character(len=*), parameter   ::  rname = mname//'/SetDC'
    
    ! --- local --------------------------------
    
    real      												::  alf
    real,allocatable									:: w(:)
    integer, allocatable 							:: ny_int(:),nx_int(:)
    integer 													:: n_cells_int,h
    integer,allocatable								:: agrup(:)
    
    !real      ::  alf(nx,ny)
    
    ! --- begin --------------------------------

    ! check if index is within size range
    if ( (ind < 1) .or. (ind > nnoise) ) then
      print *, 'ERROR - trying to set an illegal field within dc : ', ind
      stop 'ERROR in setdc'
    end if
    
    
    ! g(t+dt) = mu + a(dt) [g(t)-<g(t)>] + sqrt(1-a(dt)**2) s w(t)

    ! ~ init to mean:
    dc(:,:,ind,1) = 1
    !dc(:,:,ind,1) = noise_mu(ind)
    
    
    !Santiago Medellin (45,46) (46,47) (67,70) (70,80)

    !Medellin (lat(36)  lon(54)),  (lat(36)  lon(55)),   (lat(36)  lon(53)),   (lat(37)  lon(54)),   (lat(37)  lon(55)),   (lat(35)  lon(55)),   (lat(35)  lon(54)), (lat(38)  lon(56)), lat(37) lon(57)  
    !Monteria lat(111)  lon(43),   lat(112)  lon(43),   lat(112)  lon(44),   lat(111)  lon(44)
    !Turbo lat(90)  lon(16),   lat(89)  lon(16),   lat(89)  lon(17)
    !Caucasia lat(85) lon(75),   lat(84)  lon(74),   lat(84)  lon(75)
 
    !Rionegro lat(32)  lon(59),  lat(32)  lon(60),  lat(33)  lon(60)
    !La Dorada lat(12)  lon(83),  lat(11)  lon(83)
    !Puerto Berrio lat(42)  lon(89),  lat(41)  lon(89)
    !Barrancamermeja lat(56)  lon(104),  lat(56)  lon(105)

		!n_cells_int=189
        n_cells_int=243
		allocate(nx_int(n_cells_int))
		allocate(ny_int(n_cells_int))
		allocate(agrup(n_cells_int))
   ! nx_int=(/54,43,16,75,59,83,89,104,55,53,54,55,55,54,43,44,44,16,17,74,75,60,60,83,89,105/)
   ! ny_int=(/36,111,90,85,32,12,42,56,36,36,37,37,35,35,112,112,111,89,89,84,84,32,33,11,41,56/)yy

   ! nx_int=(/54,43,16,75,59,83,89,104,55,53,54,55,55,54,43,44,44,16,17,74,75,60,60,83,89,105,56,57/)
   ! ny_int=(/36,111,90,85,32,12,42,56,36,36,37,37,35,35,112,112,111,89,89,84,84,32,33,11,41,56,38,37/)

   ! Bogota (64,103),Medellin,Cali,       Barranquilla,Cartagena,Cucuta, Ibague, Villavicencia, Bucaramanga, SantaMarta, Valledupar, Pereira, Monteria, Pasto, Manizales, Caracas, Maracaibo, Valencia, Barquisimeto, Maracay, Quito

!    nx_int=(/64,65,63,64,65,63,64,65,63,  47,48,46,47,48,46,47,48,46, 37,38,36,37,38,36,37,38,36,   56,57,55,56,57,55,56,57,55,   48,47,49,48,47,49,48,47,49,      82,83,81,82,83,81,82,83,81,        51,52,50,51,52,50,51,52,50,                          69,70,68,69,70,68,69,70,68        75,76,74,75,76,74,75,76,74         63,64,62,63,64,62,63,64,62,            73,74,72,73,74,72,73,74,72,     46,47,45,46,47,45,46,47,45                  44,45,43,44,45,43,44,45,43,               28,29,27,28,29,27,28,29,27,       48,49,47,48,49,47,48,49,47,       144,145,143,144,145,143,144,145,143,    91,92,90,91,92,90,91,92,90,        132,133,131,132,133,131,132,133,131,                   117,118,116,117,118,116,117,118,116,      136,137,135,136,137,135,136,137,135,    15,16,14,15,16,14,15,16,14,/)


!    ny_int=(/103,103,103,104,104,104,102,102,102, 120,120,120,121,121,121,119,119,119,  89,89,89,88,88,88,90,90,90,     173,173,173,174,174,174,172,172,172     166,166,166,167,167,167,165,165,165     139,139,139,138,138,138,140,140,140 100,100,100,101,101,101,99,99,99                      97,97,97,98,98,98,96,96,96           130,130,130,131,131,131,129,129,129            176,176,176,177,177,177,175,175,175             167,167,167,168,168,168,166,166,166     105,105,105,106,106,106,104,104,104       148,148,148,149,149,149,147,147,147            65,65,65,66,66,66,64,64,64         107,107,107,108,108,108,106,106,106       168,168,168,169,169,169,167,167,167     169,169,169,170,170,170,168,168,168        164,164,164,165,165,165,163,163,163       163,163,163,164,164,164,162,162,162    165,165,165,166,166,166,164,164,164     49,49,49,50,50,50,48,48,48/)
	

  nx_int=(/64,65,63,64,65,63,64,65,63,47,48,46,47,48,46,47,48,46,37,38,36,37,38,36,37,38,36,56,57,55,56,57,55,56,57,55,48,47,49,48,47,49,48,47,49,82,83,81,82,83,81,82,83,81,51,52,50,51,52,50,51,52,50,69,70,68,69,70,68,69,70,68,75,76,74,75,76,74,75,76,74,63,64,62,63,64,62,63,64,62,73,74,72,73,74,72,73,74,72,46,47,45,46,47,45,46,47,45,44,45,43,44,45,43,44,45,43,28,29,27,28,29,27,28,29,27,48,49,47,48,49,47,48,49,47,144,145,143,144,145,143,144,145,143,91,92,90,91,92,90,91,92,90,132,133,131,132,133,131,132,133,131,117,118,116,117,118,116,117,118,116,136,137,135,136,137,135,136,137,135,15,16,14,15,16,14,15,16,14,128,129,130,128,129,130,128,129,130,68,69,70,68,69,70,68,69,70,125,126,127,125,126,127,125,126,127,125,126,127,125,126,127,125,126,127,128,129,130,128,129,130,128,129,130,64,65,66,64,65,66,64,65,66/)
    ny_int=(/103,103,103,104,104,104,102,102,102,120,120,120,121,121,121,119,119,119,89,89,89,88,88,88,90,90,90,173,173,173,174,174,174,172,172,172,166,166,166,167,167,167,165,165,165,139,139,139,138,138,138,140,140,140,100,100,100,101,101,101,99,99,99,97,97,97,98,98,98,96,96,96,130,130,130,131,131,131,129,129,129,176,176,176,177,177,177,175,175,175,167,167,167,168,168,168,166,166,166,105,105,105,106,106,106,104,104,104,148,148,148,149,149,149,147,147,147,65,65,65,66,66,66,64,64,64,107,107,107,108,108,108,106,106,106,168,168,168,169,169,169,167,167,167,169,169,169,170,170,170,168,168,168,164,164,164,165,165,165,163,163,163, 163,163,163,164,164,164,162,162,162,165,165,165,166,166,166,164,164,164,49,49,49,50,50,50,48,48,48,163,163,163,164,164,164,162,162,162,155,155,155,156,156,156,157,157,157,163,163,163,164,164,164,162,162,162,166,166,166,167,167,167,165,165,165,166,166,166,167,167,167,165,165,165,166,166,166,167,167,167,165,165,165,128,128,128,129,129,129,130,130,130/)
!    
    
   ! nx_int=(/64,65,63,64,65,63,64,65,63,47,48,46,47,48,46,47,48,46,37,38,36,37,38,36,37,38,36,56,57,55,56,57,55,56,57,55/)
   ! ny_int=(/103,103,103,104,104,104,102,102,102,120,120,120,121,121,121,119,119,119,89,89,89,88,88,88,90,90,90,173,173,173,174,174,174,172,172,172/)
    
    
agrup=(/1,1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2,2,3,3,3,3,3,3,3,3,3,4,4,4,4,4,4,4,4,4,5,5,5,5,5,5,5,5,5,6,6,6,6,6,6,6,6,6,7,7,7,7,7,7,7,7,7,8,8,8,8,8,8,8,8,8,9,9,9,9,9,9,9,9,9,10,10,10,10,10,10,10,10,10,11,11,11,11,11,11,11,11,11,12,12,12,12,12,12,12,12,12,13,13,13,13,13,13,13,13,13,14,14,14,14,14,14,14,14,14,15,15,15,15,15,15,15,15,15,16,16,16,16,16,16,16,16,16,17,17,17,17,17,17,17,17,17,18,18,18,18,18,18,18,18,18,19,19,19,19,19,19,19,19,19,20,20,20,20,20,20,20,20,20,21,21,21,21,21,21,21,21,21,22,22,22,22,22,22,22,22,22,23,23,23,23,23,23,23,23,23,24,24,24,24,24,24,24,24,24,25,25,25,25,25,25,25,25,25,26,26,26,26,26,26,26,26,26,27,27,27,27,27,27,27,27,27/)
		! draw number from normal distribution:
		allocate(w(maxval(agrup)))
	  call rnd%Get_Normal( w(:), status )

    do h=1,n_cells_int
  	  dc(nx_int(h),ny_int(h),ind,1) = noise_mu(ind)
  	  if ( present(dt_days) ) then
  	    alf = exp( - dt_days/noise_tau_days(nx_int(h),ny_int(h),ind) )
  	  	dc(nx_int(h),ny_int(h),ind,1) = dc(nx_int(h),ny_int(h),ind,1) + alf * (dc(nx_int(h),ny_int(h),ind,2)-noise_mu(ind)) 
  	  else
  	  	alf=0.0
  	  endif 
      IF_NOTOK_RETURN(status=1)
      dc(nx_int(h),ny_int(h),ind,1) = dc(nx_int(h),ny_int(h),ind,1) + sqrt(1.0-alf**2) * noise_sigma(ind) * w(agrup(h))
    enddo	

    
    ! ~ add time correlated part ?
    !if ( present(dt_days) ) then
      ! time correlation factor:
     ! alf = exp( - dt_days/noise_tau_days(:,:,ind) )
      ! relax to previous value:
      
      
      !dc(:,:,ind,1) = dc(:,:,ind,1) + alf * (dc(:,:,ind,2)-noise_mu(ind))
    !else
      ! no time correlation:
     ! alf = 0.0
    !end if

    ! ~ add noise:
    !dc(:,:,ind,1) = dc(:,:,ind,1) + sqrt(1.0-alf**2) * noise_sigma(ind) * w
    
    ! truncate to [mini,maxi] :
    dc(:,:,ind,1) = max( noise_mini(ind), dc(:,:,ind,1)                  )
    dc(:,:,ind,1) = min(                  dc(:,:,ind,1), noise_maxi(ind) )

    ! ok
    status = 0

  end subroutine SetDC


  ! ***
  
  
  subroutine ResetDC( dc )

    use LEKF_dims, only : nx, ny

    ! --- in/out ---------------------------

    real, intent(inout)   ::  dc(nx,ny,nnoise,nhist)

    ! --- local ---------------------------

    integer :: ihist

    ! --- begin ---------------------------

    ! shift the dc-array
    do ihist = 2, nhist
      dc(:,:,:,ihist) = dc(:,:,:,ihist-1)
    end do

    ! set all "present" values to zero
    dc(:,:,:,1) = 0.0

  end subroutine ResetDC
  
  
  ! ***
  
  
  ! Given list of noise names, determine analysis apply.
  ! This is used to analyze selected noise values only for certain observations.
  ! Specify a list of noise names of the form:
  !
  !     name name ... [ ; name ... ]
  !
  ! The names left from the ';' are to be analyzed, the names at the right not.
  ! This is used to avoid that some noise fields are not analyzed while they
  ! were supposed to be. The list should include all the noise names enabled in the run,
  ! and not more than that.
  ! Return value is real valued mask with values 0.0 (not analyzed) or 1.0 (analyzed),
  ! that can be used to convolve with arrays.
  
  subroutine GetNoiseApply( line, apply, status )
  
    use GO, only : goReadFromLine, goMatchValue
  
    ! --- in/out ---------------------------------
    
    character(len=*), intent(in)     ::  line
    logical, intent(out)             ::  apply(:)   ! (nnoise)
    integer, intent(out)             ::  status
    
    ! --- const ----------------------------------

    character(len=*), parameter   ::  rname = mname//'/GetNoiseApply'

    ! --- local ----------------------------------
    
    character(len=1024)            ::  names
    character(len=noise_namelen)   ::  name
    integer                        ::  inoise
    logical                        ::  flag
    logical, allocatable           ::  isset(:)
    
    ! --- begin ----------------------------------
    
    ! check ...
    if ( size(apply) /= nnoise ) then
      write (gol,'("output apply should have length ",i6," not ",i6)') nnoise, size(apply); call goErr
      TRACEBACK; status=1; return
    end if
    
    ! initialize flags to check if all values are set:
    allocate( isset(nnoise) )

    ! first start with noise names that are to be analyzed:
    flag = .true.
    ! loop over content of line:
    names = trim(line)
    do
      ! remove leading spaces:
      names = adjustl(names)
      ! empty ? then leave:
      if ( len_trim(names) == 0 ) exit
      ! strip name:
      call goReadFromLine( names, name, status, sep=' ' )
      IF_NOTOK_RETURN(status=1)
      ! switch from analyzed to not analyzed ?
      if ( trim(name) == ';' ) then
        ! next values are not to be analyzed ...
        flag = .false.
        ! next part:
        cycle
      end if
      ! search:
      call goMatchValue( trim(name), noise_name(1:nnoise), inoise, status )
      IF_NOTOK_RETURN(status=1)
      ! fill value at right position:
      apply(inoise) = flag
      ! set flag:
      isset(inoise) = .true.
    end do

    ! check on missing names ...
    if ( .not. all(isset) ) then
      write (gol,'("not all noise names included in flag definition line:")'); call goErr
      write (gol,'("  line  : ",a)') trim(line); call goErr
      write (gol,'("  number name set")'); call goErr
      do inoise = 1, nnoise
        write (gol,'(i6," ",a," (",l1,")")') inoise, trim(noise_name(inoise)), isset(inoise); call goErr
      end do
      TRACEBACK; status=1; return
    end if
    
    ! clear:
    deallocate( isset )

    ! info ...
    write (gol,'("LEKF:       noise weigts:")'); call goPr
    write (gol,'("LEKF:         line  : ",a)') trim(line); call goPr
    write (gol,'("LEKF:         number name (apply)")'); call goPr
    do inoise = 1, nnoise
      write (gol,'("LEKF:         ",i2," ",a," (",l1,")")') inoise, trim(noise_name(inoise)), apply(inoise); call goPr
    end do
    
    ! ok
    status = 0
    
  end subroutine GetNoiseApply
  
  


end module LEKF_Noise

