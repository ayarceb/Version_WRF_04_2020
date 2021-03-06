!###############################################################################
!
! GO_File  -  file utilities
!
! TYPES
!
!    type(TTextFile)     : text file, eventually commented
!
! ROUTINES
!
!    GetFileNameParts( filename, status, 
!                           dirname=, basename=, ext=, 
!                           noext=.false. )
!      Return parts of character filename.
!      If logical 'noext' is set to .true., the extension is removed
!      from the basename.
!
!    CheckDir( '/output/data.csv', status )
!      Create directory of file.
!
!###############################################################################
!
#define TRACEBACK write (*,'("in ",a," (",a,i6,")")') rname, __FILE__, __LINE__
!
#define IF_NOTOK_RETURN(action) if (status/=0) then; TRACEBACK; action; return; end if
#define IF_ERROR_RETURN(action) if (status> 0) then; TRACEBACK; action; return; end if
!
#include "go.inc"
!
!###############################################################################


module GO_File

  implicit none

  ! --- in/out -------------------

  private

  public  ::  TTextFile
  public  ::  Init, Done
  public  ::  ReadLine
  public  ::  GetFileNameParts
  public  ::  CheckDir


  ! --- const ---------------------------------
  
  character(len=*), parameter  ::  mname = 'GO_File'


  ! --- types -------------------------------------

  type TTextFile
    character(len=200)      ::  name
    ! file unit:
    integer                 ::  fu
    ! comment ?
    logical                 ::  commented
    character(len=1)        ::  comment
  end type TTextFile


  ! --- interfaces -------------------------------------

  interface Init
    module procedure file_Init
  end interface
  
  interface Done
    module procedure file_Done
  end interface
  

contains


  ! ==============================================================
  ! ===
  ! === text file
  ! ===
  ! ==============================================================


  !
  ! call Init( file, filename, iostat, [,status='unknown'|'old'|'new'] [,comment='\%'] )
  !
  ! Replaces the intrinsic 'open' command, but uses a
  ! a structure of type TTextFile instead of a file unit number. \\
  ! Arguments passed are the same as for 'open'.\\
  ! In addition, a text file can be opened as a commented
  ! text file; with the 'ReadLine' command one is able to read
  ! lines from the file while skipping the lines starting
  ! with the specified comment.
  !

  subroutine file_Init( file, filename, iostat, status, comment )

    use GO_Fu   , only : goGetFU

    ! --- in/out ------------------------

    type(TTextFile), intent(out)              ::  file
    character(len=*), intent(in)              ::  filename
    integer, intent(out)                      ::  iostat
    
    character(len=*), intent(in), optional    ::  status
    character(len=1), intent(in), optional    ::  comment

    ! --- const ---------------------------
    
    character(len=*), parameter  ::  rname = mname//'/file_Init'
    
    ! --- local ----------------------------

    logical             ::  exist    
    character(len=10)   ::  statusX

    ! --- begin ----------------------------

    ! file exist ?
    inquire( file=trim(filename), exist=exist )
    if ( .not. exist ) then
      write (*,'("commented text file not found:")')
      write (*,'("  file name : ",a)') trim(filename)
      write (*,'("in ",a)') rname; iostat=1; return
    end if

    ! check file status : 'old', 'new', 'unknown'
    if (present(status)) then
      statusX = status
    else
      statusX = 'unknown'
    end if

    ! store filename:
    file%name = filename

    ! select free file unit:
    Call goGetFU( file%fu, iostat )
    if (iostat/=0) then; write (*,'("in ",a)') rname; iostat=1; return; end if

    ! open file:
    open( unit=file%fu, file=trim(filename), iostat=iostat, &
                                 status=statusX, form='formatted' )
    if ( iostat /= 0 ) then
      write (*,'("from file open :")')
      write (*,'("  file name : ",a)') trim(filename)
      write (*,'("in ",a)') rname; iostat=1; return
    end if
    
    ! check on comment lines ?
    if ( present(comment) ) then
      file%commented = .true.
      file%comment = comment
    else
      file%commented = .false.
      file%comment = 'x'
    end if

    ! ok
    iostat = 0

  end subroutine file_Init


  ! ***


  !
  ! call Done( file )
  !

  subroutine file_Done( file, status )

    ! --- in/out -----------------

    type(TTextFile), intent(inout)    ::  file
    integer, intent(out)              ::  status

    ! --- const ----------------------
    
    character(len=*), parameter  ::  rname = mname//'/file_Done'
    
    ! --- begin ------------------------

    ! close file:
    close( unit=file%fu, iostat=status )
    if ( status /= 0 ) then
      write (*,'("from closing file:")')
      write (*,'("  ",a)') trim(file%name)
      write (*,'("in ",a)') rname; status=1; return
    end if
    
    ! ok
    status = 0

  end subroutine file_Done


  ! ***


  !
  ! call ReadLine( file, s )
  !
  ! Reads the next line from a commented text file,
  ! but skips all lines starting with the 'comment'
  ! specified with the 'Init' command.
  ! Empty lines are skipped too.
  !

  subroutine ReadLine( file, s, status  )

    ! --- in/out -------------------------

    type(TTextFile), intent(inout)      ::  file
    character(len=*), intent(out)       ::  s
    integer, intent(out)                ::  status

    ! --- const --------------------------
    
    character(len=*), parameter  ::  rname = mname//'/ReadLine'
    
    ! --- local --------------------------

    character(len=10)        ::  fmt

    ! --- begin --------------------------

    ! format (a100) etc:
    write (fmt,'("(a",i6.6,")")') len(s)

    ! loop until:
    !  o uncommented line has been read in s
    !  o eof is reached
    do
     
      ! read next line:
      read (file%fu,fmt,iostat=status) s
      if ( status < 0 ) then  ! eof
        s = ''
        status=-1; return
      else if ( status > 0 ) then
        write (*,'("reading line from file:")')
        write (*,'("  ",a)') trim(file%name)
        write (*,'("in ",a)') rname; status=1; return
      end if

      ! remove leading space:
      s = adjustl( s )

      ! empty ?
      if ( len_trim(s) == 0 ) cycle

      ! check for comment ?
      if ( file%commented .and. (scan(s,file%comment)==1) ) cycle
      
      ! s filled; leave loop
      exit
      
    end do
    
    ! ok
    status = 0

  end subroutine ReadLine


  ! ======================================================================
  ! ===
  ! === utilities
  ! ===
  ! ======================================================================
  
  subroutine GetFileNameParts( filename, status, &
                           dirname, basename, ext, noext )

    ! --- in/out -----------------------
    
    character(len=*), intent(in)              ::  filename
    integer, intent(out)                      ::  status
    
    character(len=*), intent(out), optional   ::  dirname
    character(len=*), intent(out), optional   ::  basename
    character(len=*), intent(out), optional   ::  ext
    logical, intent(in), optional             ::  noext
    
    ! --- const --------------------------
    
    character(len=*), parameter   ::  rname = mname//'/GetFileNameParts'
    
    ! --- local --------------------------
    
    integer                   ::  m, n

    ! --- begin --------------------------
    
    ! return directory part ?
    if ( present(dirname) ) then
      ! last path seperation:
      m = index( filename, '/', back=.true. )
      ! found ?
      if ( m > 1 ) then
        dirname = filename(1:m-1)
      else
        dirname = ''
      end if
    end if
    
    ! return basename part ?
    if ( present(basename) ) then
      ! last path seperation:
      m = index( filename, '/', back=.true. )
      ! lenth:
      n = len_trim(filename)
      ! found ?
      if ( m < n ) then
        ! extract:
        basename = filename(m+1:n)
        ! no-extension argument ?
        if ( present(noext) .and. noext ) then
          ! last dot:
          n = index( basename, '.', back=.true. )
          ! found ?
          if ( n == 1 ) then
            ! ".ext", return empty basename
            basename = ''
          else if ( n > 1 ) then
            ! up to character before dot:
            basename = basename(1:n-1)
          end if
        end if
      else
        ! empty:
        basename = ''
      end if
    end if
    
    ! return extension ?
    if ( present(ext) ) then
      ! last extension seperation:
      m = index( filename, '.', back=.true. )
      ! lenth:
      n = len_trim(filename)
      ! found ?
      if ( m > 0 ) then
        ! extract:
        if ( m == n ) then
          ext = ''
        else
          ext = filename(m+1:n)
        end if
      else
        ! empty:
        ext = ''
      end if
    end if
    
    ! ok
    status = 0
    
  end subroutine GetFileNameParts
  
  ! *
  
  subroutine CheckDir( filename, status )

#ifdef __INTEL_COMPILER
    use IFPort, only : System
#endif

    ! --- in/out -----------------------
    
    character(len=*), intent(in)              ::  filename
    integer, intent(out)                      ::  status
    
    ! --- const --------------------------
    
    character(len=*), parameter   ::  rname = mname//'/CheckDir'
    
    ! --- local --------------------------
    
    character(len=1024)     ::  dirname
    logical                 ::  exist

    ! --- begin --------------------------
    
    ! directory name:
    call GetFileNameParts( filename, status, dirname=dirname )
    IF_NOTOK_RETURN(status=1)
    ! directory in path?
    if ( len_trim(dirname) > 0 ) then
      ! check presence:
      inquire( file=trim(dirname)//'/.', exist=exist )
      ! not present?
      if ( .not. exist ) then
        ! create including parent directories:
#ifdef __INTEL_COMPILER
        status = System( 'mkdir -p '//trim(dirname) )
        IF_NOTOK_RETURN(status=1)
#else
        call system( 'mkdir -p '//trim(dirname), status )
        IF_NOTOK_RETURN(status=1)
#endif
      end if ! dir not present yet
    end if ! dirname included
    
    ! ok
    status = 0

  end subroutine CheckDir


end module GO_File


! ###########################################################################
! ###
! ### test program
! ###
! ###########################################################################
!
! ---[test.rc]--------------------------------------
! !
! ! abcdefg
! ! 2
!
! 0000000001111111111222222222233333333334
! 1234567890123456789012345678901234567890
!
! aaa :     kasfjasfjsla;kfja;ls
!
!   !  xxxxxxxxxx
!
!       bbb  : 123
! --------------------------------------------------
!
!program test_go_file
!
!  use go_file
!  
!  type(TTextFile)     ::  file
!  character(len=25)  ::  s
!  integer             ::  status
!  
!  call Init( file, 'test.rc', status )
!  if (status/=0) stop 'error'
!  
!  do
!  
!    call ReadLine( file, s, status )
!    if (status<0) then
!      print *, 'xxx eof'
!      exit
!    else if ( status == 0 ) then
!      print *, 'xxx "'//trim(s)//'"'
!    else
!      print *, 'xxx error'
!      exit
!    end if
!
!  end do
!  
!  call Done( file, status )
!  if (status/=0) stop 'error'
!
!
!end program test_go_file
!
