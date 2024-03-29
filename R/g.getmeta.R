g.getmeta = function(datafile,desiredtz = c(),windowsizes = c(5,900,3600),
                     daylimit=FALSE,offset=c(0,0,0),scale=c(1,1,1),tempoffset = c(0,0,0),
                     do.bfen=FALSE,do.enmo=TRUE,do.lfenmo=FALSE,
                     do.en=FALSE,do.hfen=FALSE,
                     do.hfenplus=FALSE, do.mad=FALSE,
                     do.anglex=FALSE,do.angley=FALSE,do.anglez=FALSE,
                     do.roll_med_acc_x=FALSE,do.roll_med_acc_y=FALSE,do.roll_med_acc_z=FALSE,
                     do.dev_roll_med_acc_x=FALSE,do.dev_roll_med_acc_y=FALSE,do.dev_roll_med_acc_z=FALSE,do.enmoa=FALSE,
                     lb = 0.2, hb = 15,  n = 4,meantempcal=c(),chunksize=c(),selectdaysfile=c(),
                     dayborder=0,dynrange=c(),configtz=c(),...) {
  #get input variables
  input = list(...)
  if (length(input) > 0) {
    for (i in 1:length(names(input))) {
      txt = paste(names(input)[i],"=",input[i],sep="")
      if (class(unlist(input[i])) == "character") {
        txt = paste(names(input)[i],"='",unlist(input[i]),"'",sep="")
      }
      eval(parse(text=txt))
    }
  }
  if (length(which(ls() == "outputdir")) != 0) outputdir = input$outputdir
  if (length(which(ls() == "outputfolder")) != 0) outputfolder = input$outputfolder
  metrics2do = data.frame(do.bfen,do.enmo,do.lfenmo,do.en,do.hfen,
                    do.hfenplus,do.mad,do.anglex,do.angley,do.anglez,do.roll_med_acc_x,do.roll_med_acc_y,do.roll_med_acc_z,
                    do.dev_roll_med_acc_x,do.dev_roll_med_acc_y,do.dev_roll_med_acc_z,do.enmoa)

  if (length(chunksize) == 0) chunksize = 1
  if (chunksize > 1) chunksize = 1
  if (chunksize < 0.2) chunksize = 0.2
  nmetrics = sum(c(do.bfen,do.enmo,do.lfenmo,do.en,do.hfen,do.hfenplus,do.mad,
                   do.anglex,do.angley,do.anglez,
                   do.roll_med_acc_x,do.roll_med_acc_y,do.roll_med_acc_z,
                   do.dev_roll_med_acc_x,do.dev_roll_med_acc_y,do.dev_roll_med_acc_z,do.enmoa))
  if (length(nmetrics) == 0) {
    cat("\nWARNING: No metrics selected\n")
  }
  filename = unlist(strsplit(as.character(datafile),"/"))
  filename = filename[length(filename)]
  #   #parameters
  ws3 = windowsizes[1] ; ws2 = windowsizes[2]; ws = windowsizes[3]  #window sizes
  if ((ws2/300) != round(ws2/300)) {
    ws2 = as.numeric(300 * round(ws2/300))
    cat("\nWARNING: The long windowsize needs to be a multitude of five minutes periods. The\n")
    cat(paste("\nlong windowsize has now been automatically adjusted to: ",ws2," seconds in order to meet this criteria.\n",sep=""))
  }
  if ((ws2/ws3) != round(ws2/ws3)) {
    def = c(1,5,10,15,20,30,60)
    def2 = abs(def - ws3)
    ws3 = as.numeric(def[which(def2 == min(def2))])
    cat("\nWARNING: The long windowsize needs to be a multitude of short windowsize. The \n")
    cat(paste("\nshort windowsize has now been automatically adjusted to: ",ws3," seconds in order to meet this criteria.\n",sep=""))
  }
  windowsizes = c(ws3,ws2,ws)
  PreviousEndPage = c() # needed for g.readaccfile
  start_meas = ws2/60 #ensures that first window starts at logical timepoint relative to its size (15,30,45 or 60 minutes of each hour)
  monnames = c("genea","geneactive","actigraph","axivity") #monitor names
  filequality = data.frame(filetooshort=FALSE,filecorrupt=FALSE,filedoesnotholdday = FALSE,NFilePagesSkipped = 0)
  # filecorrupt = FALSE
  # filetooshort = FALSE
  # filedoesnotholdday = FALSE
  i = 1 #counter to keep track of which binary block is being read
  count = 1 #counter to keep track of the number of seconds that have been read
  count2 = 1 #count number of blocks read with length "ws2" (15 minutes or whatever is specified above)
  LD = 2 #dummy variable used to identify end of file and to make the process stop
  bsc_qc = data.frame(time=c(),size=c(), stringsAsFactors = FALSE)
  # inspect file

  if (length(unlist(strsplit(datafile,"[.]RD"))) > 1) {
    useRDA = TRUE
  } else {
    useRDA = FALSE
  }
  options(warn=-1)
  if (useRDA == FALSE) {
    INFI = g.inspectfile(datafile, desiredtz=desiredtz)  # Check which file type and monitor brand it is
  } else {
    load(datafile)
    INFI = I
    sf = INFI$sf #= sf #new line
  }
  options(warn=0)
  mon = INFI$monc
  dformat = INFI$dformc
  sf = INFI$sf
  if (sf == 0) sf = 80 #assume 80Hertz in the absense of any other info
  header = INFI$header
  options(warn=-1)
  if (useRDA == FALSE) decn =g.dotorcomma(datafile,dformat,mon=mon, desiredtz=desiredtz)
  options(warn=0)
  # setting size of blocks that are loaded (too low slows down the process)
  # the setting below loads blocks size of 24 hours (modify if causing memory problems)
  blocksize = round(14512 * (sf/50) * chunksize)
  if (mon == 1) blocksize = round(21467 * (sf/80)  * chunksize)
  if (mon == 3 & dformat == 2) blocksize = round(blocksize)#round(blocksize/5) # Actigraph
  if (mon == 4 & dformat == 3) blocksize = round(1440 * chunksize)
  if (mon == 4 & dformat == 4) blocksize = round(blocksize * 1.0043)
  if (mon == 4 & dformat == 2) blocksize = round(blocksize)
  id = g.getidfromheaderobject(filename=filename,header=header,dformat=dformat,mon=mon)
  #creating matrixes for storing output
  S = matrix(0,0,4) #dummy variable needed to cope with head-tailing succeeding blocks of data
  nev = 80*10^7 # number expected values
  # NR = ceiling((90*10^6) / (sf*ws3)) + 1000 #NR = number of 'ws3' second rows (this is for 10 days at 80 Hz)
  NR = ceiling(nev / (sf*ws3)) + 1000 #NR = number of 'ws3' second rows (this is for 10 days at 80 Hz)
  metashort = matrix(" ",NR,(1+nmetrics)) #generating output matrix for acceleration signal
  if (mon == 1 | mon == 3 | (mon == 4 & dformat == 3) | (mon == 4 & dformat == 2)) {
    temp.available = FALSE
  } else if (mon == 2 | (mon == 4 & dformat == 4)){
    temp.available = TRUE
  }
  if (temp.available == FALSE) {
    metalong = matrix(" ",((nev/(sf*ws2))+100),4) #generating output matrix for 15 minutes summaries
  } else if (temp.available == TRUE){
    metalong = matrix(" ",((nev/(sf*ws2))+100),7) #generating output matrix for 15 minutes summaries
  }

  #------------------------------------------

  if (length(unlist(strsplit(datafile,"[.]RD"))) > 1) {
    useRDA = TRUE
  } else {
    useRDA = FALSE
  }
  #===============================================
  # Read file
  switchoffLD = 0 #dummy variable part "end of loop mechanism"
  while (LD > 1) {
    P = c()
    if (i  == 1) {
      cat(paste("\nLoading chunk: ",i,sep=""))
    } else {
      cat(paste(" ",i,sep=""))
    }
    options(warn=-1) #turn off warnings (code complains about unequal rowlengths
    if (useRDA == FALSE) {
      accread = g.readaccfile(filename=datafile,blocksize=blocksize,blocknumber=i,
                              selectdaysfile = selectdaysfile,filequality=filequality,decn=decn,
                              dayborder=dayborder,ws=ws,desiredtz=desiredtz,PreviousEndPage=PreviousEndPage,
                              inspectfileobject=INFI,configtz=configtz)
      P = accread$P
      filequality = accread$filequality
      filetooshort = filequality$filetooshort
      filecorrupt = filequality$filecorrupt
      filedoesnotholdday = filequality$filedoesnotholdday
      NFilePagesSkipped = filequality$NFilePagesSkipped
      switchoffLD = accread$switchoffLD
      PreviousEndPage = accread$endpage
    } else {
      filetooshort = FALSE
      filecorrupt = FALSE
      filedoesnotholdday = FALSE
      NFilePagesSkipped = 0
    }
    options(warn=0) #turn on warnings
    #============
    #process data as read from binary file
    if (useRDA == TRUE) {
      if (i == 1) {
        P = 1
      } else {
        P = c()
      }
    }
    if (length(P) > 0) { #would have been set to zero if file was corrupt or empty
      if (useRDA == FALSE) {
        if (mon == 1 & dformat == 1) {
          data = P$rawxyz / 1000 #convert mg output to g for genea
        } else if (mon == 2  & dformat == 1) {
          data = P$data.out
        } else if (dformat == 2) {
          data = P #as.matrix(P,dimnames = list(rownames(P),colnames(P)))
        } else if (dformat == 3) {
          data = P$rawxyz
        } else if (dformat == 4) {
          data = P$data
        }

        #add left over data from last time
        if (nrow(S) > 0) {
          data = rbind(S,data)
        }
        if (mon == 2 | (mon == 4 & dformat == 4)) {
          if (mon == 2) tempcolumn = 7
          if (mon == 4) tempcolumn = 5
          meantemp = mean(as.numeric(data[,tempcolumn]),na.rm=TRUE)
          if (is.na(meantemp) == T) { #mean(as.numeric(data[1:10,7]))
            cat("\ntemperature is NA\n")
            meantemp = 0
          } else if (mean(as.numeric(data[1:10,tempcolumn])) > 50) {
            cat("\ntemperature value is unreaslistically high (> 50 Celcius)\n")
            meantemp = 0
          }
        }
        # extraction and modification of starting point of measurement
        if (i == 1 | (i != 1 & length(selectdaysfile) > 0)) { #only do this for first block of data
          starttime = g.getstarttime(datafile=datafile,P=P,header=header,mon=mon,
                                     dformat=dformat,desiredtz=desiredtz,selectdaysfile=selectdaysfile)
          #==================================================
          #inspection timezone
          timezone = attr(unclass(as.POSIXlt(starttime[1])),which="tzone")
          starttimebefore = as.POSIXlt(starttime)
          # assuming that timestamps is good, but that timezone might be lost in conversion from string to POSIXct
          if (dformat == 1) { #not sure whether this is required for csv-format (2)
            if (length(which(timezone == "GMT")) > 0) {
              if (length(desiredtz) == 0) {
                print("desiredtz not specified, Europe/London used as default")
                desiredtz = "Europe/London"
              }
              starttime = as.POSIXlt(starttime[1],tz=desiredtz)
            }
          }
          #================================================
          #assess weekday
          wday = unclass(as.POSIXlt(starttime[1]))$wday #day of the week 0-6 and 0 is Sunday
          wday = wday + 1
          weekdays = c("Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday")
          wdayname = weekdays[wday]
          #======================================================
          #assess how much data to delete till next 15 minute period
          temp = unlist(strsplit(as.character(starttime)," "))
          if (length(temp) > 1) {
            starttime2 = as.numeric(unlist(strsplit(temp[2],":")))
          } else {
            # first get char to POSIX
            # temp = as.POSIXlt(starttime,format="%Y-%m-%dT%H:%M:%S%z",tz="Europe/London")
            temp = iso8601chartime2POSIX(starttime,tz=desiredtz)
            # temp2 = format(temp,"%H:%M:%S") # extract time
            temp = unlist(strsplit(as.character(temp)," ")) # to keep it consistent with what we had
            starttime2 = as.numeric(unlist(strsplit(as.character(temp[2]),":")))
          }
          if (length(which(is.na(starttime2) ==  TRUE)) > 0 | length(starttime2) ==0) { #modified on 5may2015
            starttime2 = c(0,0,0)
          }
          start_hr = as.numeric(starttime2[1])
          start_min = as.numeric(starttime2[2])
          start_sec = as.numeric(starttime2[3])
          secshift = 60 - start_sec #shift in seconds needed
          start_min = start_min +1 #shift in minutes needed (+1 one to account for seconds comp)
          #-----------
          minshift = start_meas - (((start_min/start_meas) - floor(start_min/start_meas)) * start_meas)
          # minshift = minshift - 1 # Removed as suggested by E Mirkes
          if (minshift == start_meas) minshift = 0; # Addition as suggested by E Mirkes: One of my files has the first record at 2016-02-11 13:14:55 but the resulting file contains data from 2016-02-11 13:30:00. It means that we lost 15 minutes.
          #-----------
          sampleshift = (minshift*60*sf) + (secshift*sf) #derive sample shift
          data = data[-c(1:floor(sampleshift)),] #delete data accordingly
          newmin = start_min+minshift #recalculate first timestamp
          newsec = 0
          # newsec = start_sec+secshift # Removed as suggested by E Mirkes
          # if (newsec >= 60) { # Removed as suggested by E Mirkes
          #   newsec = newsec - 60 # Removed as suggested by E Mirkes
          #   newmin = newmin + 1 # Removed as suggested by E Mirkes
          # } # Removed as suggested by E Mirkes
          remem2add24 = FALSE
          if (newmin >= 60) {
            newmin = newmin - 60
            start_hr = start_hr + 1
            if (start_hr == 24) { #if measurement is started in 15 minutes before midnight
              #there used to be a nasty hack here for measurements that start in the 15 minutes before midnight, now fixed
              start_hr = 0
              remem2add24 = TRUE #remember to add 24 hours because this is now the wrong day
            }
          }
          starttime3 = paste(temp[1]," ",start_hr,":",newmin,":",newsec,sep="") #<<<====  changed 17-12-2013
          #create timestamp from string (now desiredtz is added)
          if (length(desiredtz) == 0) {
            print("desiredtz not specified, Europe/London used as default")
            desiredtz = "Europe/London"
          }
          starttime_a = as.POSIXct(starttime3,format="%d/%m/%Y %H:%M:%S",tz=desiredtz) #,origin="1970-01-01"
          starttime_b = as.POSIXct(starttime3,format="%d-%m-%Y %H:%M:%S",tz=desiredtz) #,origin="1970-01-01"
          starttime_c = as.POSIXct(starttime3,format="%Y/%m/%d %H:%M:%S",tz=desiredtz) #,origin="1970-01-01"
          starttime_d = as.POSIXct(starttime3,format="%Y-%m-%d %H:%M:%S",tz=desiredtz) #,origin="1970-01-01"
          if (is.na(starttime_a) == FALSE) {
            starttime = starttime_a
          } else {
            if (is.na(starttime_b) == FALSE) {
              starttime = starttime_b
            } else {
              if (is.na(starttime_c) == FALSE) {
                starttime = starttime_c
              } else {
                if (is.na(starttime_d) == FALSE) {
                  starttime = starttime_d
                } else {
                  cat("\ndate not recognized\n")
                }
              }
            }
          }
          if (remem2add24 == TRUE) {
            starttime = as.POSIXlt(as.numeric(starttime) + (24*3600),origin="1970-01-01")
          }
        }
        LD = nrow(data)
        if (LD < (ws*sf) & i == 1) {
          cat("\nError: data too short for doing non-wear detection 3\n")
          switchoffLD = 1
          LD = 0 #ignore rest of the data and store what has been loaded so far.
        }
      } else { # if useRDA == TRUE
        LD = length(Gx)
      }
      # if (useRDA == TRUE) LD = 1
      #store data that could not be used for this block, but will be added to next block
      if (LD >= (ws*sf)) { # LD != 0
        if (useRDA == FALSE) {
          use = (floor(LD / (ws2*sf))) * (ws2*sf) #number of datapoint to use # changes from ws to ws2 Vvh 23/4/2017
          if (use != LD) {
            S = as.matrix(data[(use+1):LD,]) #store left over
            if (ncol(S) == 1) {
              S = t(S)
            }
          } else { #use all data
            S = matrix(0,0,ncol(data))
          }
          data = as.matrix(data[1:use,])

          LD = nrow(data) #redefine LD because there is less data
          ##==================================================
          # Feature calculation
          dur = nrow(data)	#duration of experiment in data points
          durexp = nrow(data) / (sf*ws)	#duration of experiment in hrs
          data = as.matrix(data)
          # Initialization of variables
          if (mon == 1) {
            data[,1:3] = scale(data[,1:3],center = -offset, scale = 1/scale) #rescale data
            Gx = as.numeric(data[,1]); Gy = as.numeric(data[,2]); Gz = as.numeric(data[,3])
          } else if (mon == 4 & dformat == 3) {
            data[,1:3] = scale(data[,1:3],center = -offset, scale = 1/scale) #rescale data
            Gx = as.numeric(data[,1]); Gy = as.numeric(data[,2]); Gz = as.numeric(data[,3])
          } else if (mon == 4 & (dformat == 4 |  dformat == 2)) {
            data[,2:4] = scale(data[,2:4],center = -offset, scale = 1/scale) #rescale data
            Gx = as.numeric(data[,2]); Gy = as.numeric(data[,3]); Gz = as.numeric(data[,4])
          } else if (mon == 2 & dformat == 1) {
            yy = as.matrix(cbind(as.numeric(data[,7]),as.numeric(data[,7]),as.numeric(data[,7])))
            data[,2:4] = scale(as.matrix(data[,2:4]),center = -offset, scale = 1/scale) +
              scale(yy, center = rep(meantemp,3), scale = 1/tempoffset)  #rescale data
            Gx = as.numeric(data[,2]); Gy = as.numeric(data[,3]); Gz = as.numeric(data[,4])
          } else if (dformat == 2 & (mon != 4)) {
            data2 = matrix(NA,nrow(data),3)
            if (ncol(data) == 3) extra = 0
            if (ncol(data) >= 4) extra = 1
            for (jij in 1:3) {
              data2[,jij] = as.numeric(data[,(jij+extra)])
            }
            if (mon == 3) {
              data2[,1:3] = scale(data2[,1:3],center = -offset, scale = 1/scale)  #rescale data
            } else if (mon == 2) {
              yy = as.matrix(cbind(as.numeric(data[,7]),as.numeric(data[,7]),as.numeric(data[,7])))
              meantemp = mean(as.numeric(data[,7]))
              # meantemp replaced by meantempcal # 19-12-2013
              if (length(meantempcal) == 0) {
                meantempcal = meantemp
              }
              data2[,1:3] = scale(data2[,1:3],center = -offset, scale = 1/scale) +
                scale(yy, center = rep(meantempcal,3), scale = 1/tempoffset)  #rescale data
            }
            Gx = as.numeric(data2[,1]); Gy = as.numeric(data2[,2]); Gz = as.numeric(data2[,3])
          }
          #--------------------------------------------
          if (mon == 2 | (mon == 4 & dformat == 4)) {
            if (mon == 2) {
              temperaturecolumn = 7; lightcolumn = 5
            } else if (mon ==4) {
              temperaturecolumn = 5; lightcolumn = 7
            }
            light = as.numeric(data[,lightcolumn])
            temperature = as.numeric(data[,temperaturecolumn])
          }
          #####
          # STORE THE RAW DATA
          # Gx, Gy, Gz, starttime, (temperature, light)
          if (length(selectdaysfile) > 0) {
            path3 = paste(outputdir,outputfolder,sep="") #where is output stored?
            # calculate extra timestamp in a more complete format
            # i am doing this here and not at the top of the code, because at this point the starttime has already be adjusted
            # to the starttime of the first epoch in the data
            # starttime_aschar_tz = strftime(as.POSIXlt(as.POSIXct(starttime),tz=desiredtz),format="%Y-%m-%d %H:%M:%S %z")
            if (mon == 2 | (mon == 4 & dformat == 4)) {
              I = INFI
              save(I,sf,wday,wdayname,decn,Gx,Gy,Gz,starttime,temperature,light,
                   file = paste(path3,"/meta/raw/",filename,"_day",i,".RData",sep=""))
            } else {
              save(I,sf,wday,wdayname,decn,Gx,Gy,Gz,starttime,
                   file = paste(path3,"/meta/raw/",filename,"_day",i,".RData",sep=""))
            }
          }
        } else {
          #           load(datafile) # turned off because datafile will already be loaded (earlier on in script)
          data = cbind(rep(0,length(Gx)),Gx,Gy,Gz)
          LD = nrow(data)
        }
        EN = sqrt(Gx^2 + Gy^2 + Gz^2)
        allmetrics = g.applymetrics(Gx,Gy,Gz,n,sf,ws3,metrics2do)
        # attach(allmetrics,warn.conflicts = FALSE)
        # globalVariables(c("BFEN3b","ENMO3b","LFENMO3b","EN3b","HFEN3b",
        #                   "HFENplus3b", "MAD3b", "angle_x3b","angle_y3b","angle_z3b",
        #                   "roll_med_acc_x3b","roll_med_acc_y3b","roll_med_acc_z3b","dev_roll_med_acc_x3b",
        #                   "dev_roll_med_acc_y3b","dev_roll_med_acc_z3b"))
        BFEN3b = allmetrics$BFEN3b
        ENMO3b = allmetrics$ENMO3b
        ENMOa3b = allmetrics$ENMOa3b
        LFENMO3b = allmetrics$LFENMO3b
        EN3b = allmetrics$EN3b
        HFEN3b = allmetrics$HFEN3b
        HFENplus3b = allmetrics$HFENplus3b
        MAD3b = allmetrics$MAD3b
        angle_x3b = allmetrics$angle_x3b
        angle_y3b = allmetrics$angle_y3b
        angle_z3b = allmetrics$angle_z3b
        roll_med_acc_x3b = allmetrics$roll_med_acc_x3b
        roll_med_acc_y3b = allmetrics$roll_med_acc_y3b
        roll_med_acc_z3b = allmetrics$roll_med_acc_z3b
        dev_roll_med_acc_x3b = allmetrics$dev_roll_med_acc_x3b
        dev_roll_med_acc_y3b = allmetrics$dev_roll_med_acc_y3b
        dev_roll_med_acc_z3b = allmetrics$dev_roll_med_acc_z3b
      }
      if (LD >= (ws*sf)) { #LD != 0
        #-----------------------------------------------------
        #extend out if it is expected to be too short
        if (count > (nrow(metashort) - (2.5*(3600/ws3) *24))) {
          extension = matrix(" ",((3600/ws3) *24),ncol(metashort)) #add another day to metashort once you reach the end of it
          metashort = rbind(metashort,extension)
          extension2 = matrix(" ",((3600/ws2) *24),ncol(metalong)) #add another day to metashort once you reach the end of it
          metalong = rbind(metalong,extension2)

          cat("\nvariable metashort extended\n")
        }
        col_msi = 2
        if (do.bfen == TRUE) {
          metashort[count:(count-1+length(BFEN3b)),col_msi] = BFEN3b; col_msi = col_msi + 1
        }
        if (do.enmo == TRUE) {
          metashort[count:(count-1+length(ENMO3b)),col_msi] = ENMO3b; col_msi = col_msi + 1
        }
        if (do.lfenmo == TRUE) {
          metashort[count:(count-1+length(LFENMO3b)),col_msi] = LFENMO3b; col_msi = col_msi + 1
        }
        if (do.en == TRUE) {
          metashort[count:(count-1+length(EN3b)),col_msi] = EN3b; col_msi = col_msi + 1
        }
        if (do.hfen == TRUE) {
          metashort[count:(count-1+length(HFEN3b)),col_msi] = HFEN3b; col_msi = col_msi + 1
        }
        if (do.hfenplus == TRUE) {
          metashort[count:(count-1+length(HFENplus3b)),col_msi] = HFENplus3b; col_msi = col_msi + 1
        }
        if (do.mad == TRUE) {
          metashort[count:(count-1+length(MAD3b)),col_msi] = MAD3b; col_msi = col_msi + 1
        }
        if (do.anglex == TRUE) {
          metashort[count:(count-1+length(angle_x3b)),col_msi] = angle_x3b; col_msi = col_msi + 1
        }
        if (do.angley == TRUE) {
          metashort[count:(count-1+length(angle_y3b)),col_msi] = angle_y3b; col_msi = col_msi + 1
        }
        if (do.anglez == TRUE) {
          metashort[count:(count-1+length(angle_z3b)),col_msi] = angle_z3b; col_msi = col_msi + 1
        }
        if (do.roll_med_acc_x == TRUE) {
          metashort[count:(count-1+length(roll_med_acc_x3b)),col_msi] = roll_med_acc_x3b; col_msi = col_msi + 1
        }
        if (do.roll_med_acc_y == TRUE) {
          metashort[count:(count-1+length(roll_med_acc_y3b)),col_msi] = roll_med_acc_y3b; col_msi = col_msi + 1
        }
        if (do.roll_med_acc_z == TRUE) {
          metashort[count:(count-1+length(roll_med_acc_z3b)),col_msi] = roll_med_acc_z3b; col_msi = col_msi + 1
        }
        if (do.dev_roll_med_acc_x == TRUE) {
          metashort[count:(count-1+length(dev_roll_med_acc_x3b)),col_msi] = dev_roll_med_acc_x3b; col_msi = col_msi + 1
        }
        if (do.dev_roll_med_acc_y == TRUE) {
          metashort[count:(count-1+length(dev_roll_med_acc_y3b)),col_msi] = dev_roll_med_acc_y3b; col_msi = col_msi + 1
        }
        if (do.dev_roll_med_acc_z == TRUE) {
          metashort[count:(count-1+length(dev_roll_med_acc_z3b)),col_msi] = dev_roll_med_acc_z3b; col_msi = col_msi + 1
        }
        if (do.enmoa == TRUE) {
          metashort[count:(count-1+length(ENMOa3b)),col_msi] = ENMOa3b; col_msi = col_msi + 1
        }
        count = count + length(EN3b) #increasing "count" the indicator of how many seconds have been read

        rm(Gx); rm(Gy); rm(Gz); rm(allmetrics)
        # update blocksize depending on available memory
        BlocksizeNew = updateBlocksize(blocksize=blocksize, bsc_qc=bsc_qc)
        bsc_qc = BlocksizeNew$bsc_qc
        blocksize = BlocksizeNew$blocksize
        ##==================================================
        # MODULE 2 - non-wear time & clipping
        #cat("\nmodule 2\n") #notice that windows overlap for non-wear detecting
        window2 = ws2 * sf #window size in samples
        window = ws * sf #window size in samples
        nmin = floor(LD/(window2)) #nmin = minimum number of windows that fit in this block of data
        CW = NW = matrix(0,nmin,3) #CW is clipping, NW is non-wear
        TS1W = TS2W = TS3W = TS4W = TS5W = TS6W = TS7W = CWav = NWav = matrix(0,nmin,1)
        for (h in 1: nmin) { #number of windows
          cliphoc1 = (((h-1)*window2)+ window2*0.5 ) - window2*0.5 #does not use "window"
          cliphoc2 = (((h-1)*window2)+ window2*0.5 ) + window2*0.5
          for (jj in  1:3) {
            #hoc1 & hoc2 = edges of windows
            #window is bigger& window2 is smaller one
            crit = ((window/window2)/2)+1
            if (h <= crit) {
              hoc1 = 1
              hoc2 = window
            } else if (h >= (nmin - crit)) {
              hoc1 = (nmin-crit)*window2
              hoc2 = nmin*window2 #end of data
            } else if (h > crit & h < (nmin - crit)) {
              hoc1=(((h-1)*window2)+ window2*0.5 ) - window*0.5
              hoc2=(((h-1)*window2)+ window2*0.5 ) + window*0.5
            }
            if (dformat == 1) {
              sdwacc = sd(as.numeric(data[(1+hoc1):hoc2,(jj+(mon-1))]),na.rm=TRUE)
              maxwacc = max(as.numeric(data[(1+hoc1):hoc2,(jj+(mon-1))]),na.rm=TRUE)
              minwacc = min(as.numeric(data[(1+hoc1):hoc2,(jj+(mon-1))]),na.rm=TRUE)
            } else if (dformat == 2 | dformat == 4) {
              if (ncol(data) == 3) extra = 0
              if (ncol(data) >= 4) extra = 1
              sdwacc = sd(as.numeric(data[(1+hoc1):hoc2,(jj+extra)]),na.rm=TRUE)
              maxwacc = max(as.numeric(data[(1+hoc1):hoc2,(jj+extra)]),na.rm=TRUE)
              minwacc = min(as.numeric(data[(1+hoc1):hoc2,(jj+extra)]),na.rm=TRUE)
            } else if (dformat == 3) {
              sdwacc = sd(as.numeric(data[(1+hoc1):hoc2,jj]),na.rm=TRUE)
              maxwacc = max(as.numeric(data[(1+hoc1):hoc2,jj]),na.rm=TRUE)
              minwacc = min(as.numeric(data[(1+hoc1):hoc2,jj]),na.rm=TRUE)
            }
            #estimate number of data points of clipping based on raw data at about 87 Hz
            if (length(dynrange) > 0) {
              clipthres = dynrange - 0.5
            } else {
              if (mon == 1) {
                clipthres = 5.5
              } else if (mon == 2) {
                clipthres = 7.5
              } else if (mon == 3) {
                clipthres = 7.5 # hard coded assumption that dynamic range is 8g
              } else if (mon == 4) {
                clipthres = 7.5 # hard coded assumption that dynamic range is 8g
              }
            }

            if (dformat == 1) {
              CW[h,jj] = length(which(abs(as.numeric(data[(1+cliphoc1):cliphoc2,(jj+(mon-1))])) > clipthres))
            } else if (dformat == 2 | dformat == 4) {
              if (ncol(data) == 3) extra = 0
              if (ncol(data) >= 4) extra = 1
              CW[h,jj] = length(which(abs(as.numeric(data[(1+cliphoc1):cliphoc2,(jj+extra)])) > clipthres))
            } else if (dformat == 3) {
              CW[h,jj] = length(which(abs(as.numeric(data[(1+cliphoc1):cliphoc2,jj])) > clipthres))
            }
            #non-wear criteria are monitor specific
            if (mon == 1) {
              sdcriter = 0.003
              racriter = 0.05
            } else if (mon == 2) {
              sdcriter = 0.013 #0.0109 in rest test
              racriter = 0.15 #0.1279 measured in rest test
            } else if (mon == 3) {
              sdcriter = 0.013 #ADJUSTMENT NEEDED FOR ACTIGRAPH???????????
              racriter = 0.15 #ADJUSTMENT NEEDED FOR ACTIGRAPH???????????
            } else if (mon == 4) {
              sdcriter = 0.013 #ADJUSTMENT NEEDED FOR Axivity???????????
              racriter = 0.15 #ADJUSTMENT NEEDED FOR Axivity???????????
            }
            if (sdwacc < sdcriter) {
              if (abs(maxwacc - minwacc) < racriter) {
                NW[h,jj] = 1
              }
            } else {
            }

          }
          CW = CW / (window2) #changed 30-1-2012, was window*sf
          NWav[h,1] = (NW[h,1] + NW[h,2] + NW[h,3]) #indicator of non-wear
          CWav[h,1] = max(c(CW[h,1],CW[h,2],CW[h,3])) #indicator of clipping
        }
        col_mli = 2
        metalong[count2:((count2-1)+nrow(NWav)),col_mli] = NWav; col_mli = col_mli + 1
        metalong[(count2):((count2-1)+nrow(NWav)),col_mli] = CWav; col_mli = col_mli + 1
        if (mon == 2 | (mon == 4 & dformat == 4)) { #going from sample to ws2
          #light (running mean)
          lightc = cumsum(c(0,light))
          select = seq(1,length(lightc),by=(ws2*sf))
          lightmean = diff(lightc[round(select)]) / abs(diff(round(select)))
          #light (running max)
          lightmax = matrix(0,length(lightmean),1)
          for (li in 1:(length(light)/(ws2*sf))) {
            tempm = max(light[((li-1)*(ws2*sf)):(li*(ws2*sf))])
            if (length(tempm) > 0) {
              lightmax[li] = tempm[1]
            } else {
              lightmax[li] = max(light[((li-1)*(ws2*sf)):(li*(ws2*sf))])
            }
          }
          #temperature (running mean)
          temperaturec = cumsum(c(0,temperature))
          select = seq(1,length(temperaturec),by=(ws2*sf))
          temperatureb = diff(temperaturec[round(select)]) / abs(diff(round(select)))
        }
        #EN going from sample to ws2

        ENc = cumsum(c(0,EN))
        select = seq(1,length(ENc),by=(ws2*sf))
        ENb = diff(ENc[round(select)]) / abs(diff(round(select)))
        if (mon == 2 | (mon == 4 & dformat == 4)) {
          metalong[(count2):((count2-1)+nrow(NWav)),col_mli] = lightmean; col_mli= col_mli + 1
          metalong[(count2):((count2-1)+nrow(NWav)),col_mli] = lightmax; col_mli= col_mli + 1
          metalong[(count2):((count2-1)+nrow(NWav)),col_mli] = temperatureb; col_mli= col_mli + 1
        }
        metalong[(count2):((count2-1)+nrow(NWav)),col_mli] = ENb; col_mli= col_mli + 1
        count2  = count2 + nmin
        rm(P)
        gc()
      } #end of section which is skipped when switchoff == 1
    } else {
      LD = 0 #once LD < 1 the analysis stops, so this is a trick to stop it
      # cat("\nstop reading because there is not enough data in this block\n")
    }
    if (switchoffLD == 1) {
      LD = 0
    }
    if (ceiling(daylimit) != FALSE) {
      if (i == ceiling(daylimit)) { #to speed up testing only read first 'i' blocks of data
        LD = 0 #once LD < 1 the analysis stops, so this is a trick to stop it
        cat(paste("\nstopped reading data because this analysis is limited to ",ceiling(daylimit)," days\n",sep=""))
      }
    }
    i = i + 1 #go to next block
  }
  # deriving timestamps
  if (filecorrupt == FALSE & filetooshort == FALSE & filedoesnotholdday == FALSE) {
    # cut = (count+1):nrow(metashort) # how it was
    cut = count:nrow(metashort)
    if (length(cut) > 1) {
      metashort = as.matrix(metashort[-cut,])
    }
    if (nrow(metashort) > 1) {
      starttime3 = round(as.numeric(starttime)) #numeric time but relative to the desiredtz
      time5 = seq(starttime3,(starttime3+((nrow(metashort)-1)*ws3)),by=ws3)
      if (length(selectdaysfile) > 0 & length(time5) > round((24*(3600/ws3))+1)) { # (Millenium cohort)
        #===================================================================
        # All of the below needed for Millenium cohort
        SDF = read.csv(selectdaysfile)
        if (useRDA == FALSE) I = g.inspectfile(datafile, desiredtz=desiredtz)
        hvars = g.extractheadervars(I)
        SN = hvars$SN
        SDFi = which(as.numeric(SDF$Monitor) == as.numeric(SN))
        dateday1 = as.character(SDF[SDFi,2])
        dateday2 = as.character(SDF[SDFi,3])

        dtday1 = as.POSIXlt(paste0(dateday1," 01:00:00"),format="%d/%m/%Y %H:%M:%S")
        dtday2 = as.POSIXlt(paste0(dateday2," 01:00:00"),format="%d/%m/%Y %H:%M:%S")
        deltat = as.numeric(dtday2) - as.numeric(dtday1)
        delta_day = round(deltat / (3600*24)) - 1 # minus 1 because you naturally already
        # make a jump of 1 day
        daych = seq(round((24*(3600/ws3))+1),length(time5),by=1)
        if (length(daych) > (24*(3600/ws3))) {
          daych = daych[1:(24*(3600/ws3))]
        }
        time5[daych] = time5[daych] + (delta_day*24*3600) #+ 5
      }
      if (length(desiredtz) == 0) {
        print("desiredtz not specified, Europe/London used as default")
        desiredtz = "Europe/London"
      }
      time6 = as.POSIXlt(time5,origin="1970-01-01",tz=desiredtz)
      time6 = strftime(time6,format="%Y-%m-%dT%H:%M:%S%z")
      metashort[,1] = as.character(time6)
    }
    # cut2 = (count2+1):nrow(metalong)
    cut2 = (count2):nrow(metalong) # how it was
    if (length(cut2) > 1) {
      metalong = as.matrix(metalong[-cut2,])
    }
    if (nrow(metalong) > 2) {
      starttime4 = round(as.numeric(starttime)) #numeric time but relative to the desiredtz
      time1 = seq(starttime4,(starttime4+(nrow(metalong)*ws2)-1),by=ws2)

      if (length(selectdaysfile) > 0 & round((24*(3600/ws2))+1) < length(time1)) { # (Millenium cohort)
        #===================================================================
        # All of the below needed for Millenium cohort
        SDF = read.csv(selectdaysfile)
        if (useRDA == FALSE) I = g.inspectfile(datafile, desiredtz=desiredtz)
        hvars = g.extractheadervars(I)
        SN = hvars$SN
        SDFi = which(as.numeric(SDF$Monitor) == as.numeric(SN))
        if (length(SDFi) == 1) { # if SN is not in the file then this is skipped
          dateday1 = as.character(SDF[SDFi,2])
          dateday2 = as.character(SDF[SDFi,3])
          dtday1 = as.POSIXlt(paste0(dateday1," 01:00:00"),format="%d/%m/%Y %H:%M:%S")
          dtday2 = as.POSIXlt(paste0(dateday2," 01:00:00"),format="%d/%m/%Y %H:%M:%S")
          deltat = as.numeric(dtday2) - as.numeric(dtday1)
          delta_day = round(deltat / (3600*24)) - 1 # minues 1 because you naturally already make a jump of 1 day
          daych = seq(round((24*(3600/ws2))+1),length(time1),by=1)
          time1[daych] = time1[daych] + (delta_day*24*3600) #+ 5
        }
      }
      if (length(desiredtz) == 0) {
        print("desiredtz not specified, Europe/London used as default")
        desiredtz = "Europe/London"
      }
      time2 = as.POSIXlt(time1,origin="1970-01-01",tz=desiredtz)
      time2 = strftime(time2,format="%Y-%m-%dT%H:%M:%S%z")
      metalong[,1] = as.character(time2)
    }
    metricnames_short = c("timestamp","BFEN","ENMO","LFENMO","EN","HFEN","HFENplus","MAD",
                          "anglex","angley","anglez","roll_med_acc_x","roll_med_acc_y","roll_med_acc_z",
                          "dev_roll_med_acc_x","dev_roll_med_acc_y","dev_roll_med_acc_z","ENMOa") #
    metricnames_short = as.character(metricnames_short[c(TRUE,do.bfen,do.enmo,do.lfenmo,do.en,do.hfen,do.hfenplus,do.mad,
                                                         do.anglex,do.angley,do.anglez,
                                                         do.roll_med_acc_x,do.roll_med_acc_y,do.roll_med_acc_z,
                                                         do.dev_roll_med_acc_x,do.dev_roll_med_acc_y,do.dev_roll_med_acc_z,
                                                         do.enmoa)]) #
    metashort = data.frame(A = metashort,stringsAsFactors = FALSE)
    names(metashort) = metricnames_short
    for (ncolms in 2:ncol(metashort)) {
      metashort[,ncolms] = as.numeric(metashort[,ncolms])
    }

    if (mon == 1 | mon == 3 | (mon == 4 & dformat == 3) | (mon == 4 & dformat == 2)) {
      metricnames_long = c("timestamp","nonwearscore","clippingscore","en")
    } else if (mon == 2 | (mon == 4 & dformat == 4)) {
      metricnames_long = c("timestamp","nonwearscore","clippingscore","lightmean","lightpeak","temperaturemean","EN")
    }
    metalong = data.frame(A = metalong,stringsAsFactors = FALSE)
    names(metalong) = metricnames_long
    for (ncolml in 2:ncol(metalong)) {
      metalong[,ncolml] = as.numeric(metalong[,ncolml])
    }

    closeAllConnections()
  } else {
    metalong=metashort=wday=wdayname=windowsizes = c()
  }


  # detach(allmetrics,warn.conflicts = FALSE)
  if (length(metashort) == 0 | filedoesnotholdday == TRUE) filetooshort = TRUE
  invisible(list(filecorrupt=filecorrupt,filetooshort=filetooshort,NFilePagesSkipped=NFilePagesSkipped,
                 metalong=metalong, metashort=metashort,wday=wday,wdayname=wdayname,windowsizes=windowsizes,bsc_qc=bsc_qc))
}
